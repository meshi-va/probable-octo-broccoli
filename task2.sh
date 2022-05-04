#!/bin/bash
# 
version="0.1.9"
# 
# Planned features:
#
# Input validation: 
#	• If more than 2 arguments are provided, print an error and the usage.
#	• If the provided path contains unexpected characters, print an error and the usage.
# 
# ----------- Functions -----------

help () {
cat << EOF
 task2 - bash script - version: $version
 
 Usage: ./task2.sh [-h] [-v]
        ./task2.sh arg1 [arg2]
 
 task2 is a tool for copying files from a location to 
 your Lucid filespace.
 
 It takes two arguments and passes them to rsync;
    - The first argument defines the source location;
    - The second argument(optional) defines the 
      destination within your Lucid filespace.
 If a second argument is not provided, the destiantion 
 will be set to the mount point??? of your Lucid filespace.
 
 Example:
 
 # Copy the contents of the current directory to 
   'folder1' in your Lucid filespace:

         $ ./task2.sh . folder1/ 
 (Will execute 'rsync . /media/filespace/folder1/' under the hood. )

 # Copy the file 'foo.txt' to the main directory 
   in your Lucid filespace:

         $ ./task2.sh foo.txt
 (Will execute 'rsync foo.txt /media/filespace/' under the hood. )

 Available options:
  -h          Print this message.
  -v          Print script version.

EOF
}

app_status () {
    curl -s http://localhost:7778/app/status
}

client_state () {
    app_status | jq -r .clientState.state
}

dirtyBytes () {
    curl -s http://localhost:7778/cache/info | jq .dirtyBytes
}

PUT_empty_HTTP () {
    curl -s -X PUT http://localhost:7778/app/sync -w '%{http_code}'
}

# ----------- Get Options -----------
# This loop was inspired by https://opensource.com/article/19/12/help-bash-program

while getopts ":hv" option; do
   case $option in
        h) # display help
            help
            exit;;
        v) # display version
            echo version $version
            exit;;
        \?) # incorrect option
            echo "Error: Invalid option. Please use [-h] for help."
            exit;;
   esac
done

# ----------- Evironment Validation -----------

# Checks if Lucid is running
ps -fC Lucid > /dev/null || { echo "Error: Lucid isn't running" ; exit 1; }

# Checks if jq is installed 
which jq > /dev/null || { echo "jq is not installed. Please install it." ; exit 1; }

# If no argument is provided, the script exits
[[ $1 == "" ]] && { echo "Error: The source is not specified. Please use [-h] for help." ; exit 1; }

# Queries the mount point and if the mount point is "null", shows an error, then exits
mount_point=$(app_status | jq -r .mountPoint) && [[ $mount_point == "null" ]] && { echo "Error: Your filespace isn't linked" ; exit 1; }

# ----------- Useful info -----------

echo The "source" is: $1
echo The destination is: $mount_point/$2
echo 

# ----------- Copy operation -----------

# Rsync is ran in archive mode(-a) and displays the progress(--info=progress2) of the operation.
# • -O is to omit directories from having their modification times preserved. 
#       -   This could be caused by a quirk in FUSE and I am yet to diagnoze this properly and find a solution.
#
# • It uses the first argument provided to the script($1) as the source; and the second one($2) as destination.
# • It also takes the mount point using the $mount_point variable.
#       -   These two things combined allow the script to run with a single argument($1); 
#           because $2 will always default to Lucid's mountpoint.

rsync -a --info=progress2 -O $1 $mount_point/$2 || { echo "Error: rsync failed" ; exit 1; }

echo 

# ----------- dirtyBytes operation -----------

# The while loop exports the output of the $(dirtyBytes) function and adds it to the $dirtyBytes variable.
#   This variable will be then compared to 0;
#
#       - If it's greater than 0, it will print the value and wait a second before it checks the value again and exports it to the variable.
#         This will continue until the value is no longer greater than 0.
#
#       - If it's equal to 0, it will print a message and break the loop to continue with the next operation.

while dirtyBytes=$(dirtyBytes)
    do
    if [[ $dirtyBytes -gt 0 ]]; then
        echo "Remaining dirtyBytes:" $dirtyBytes
        sleep 1
    else 
        echo 
        echo "Zero dirtyBytes"
        break
    fi
done

echo 

# ----------- HTTP PUT operation -----------

# This loop pretty much follows the same logic as the previous one, but the function and the expected values are different.
# I'll need to add a way to break out of the loop and print an error after a certain tries or time has passed.
# I wasn't able to find the documentation for the internal/client API, so I am assuming that HTTP 200 is the expected code here.

while HTTP_response=$(PUT_empty_HTTP)
    do
    if [[ ! $HTTP_response -eq 200 ]]; then
        echo "Waiting for HTTP success response"
        sleep 1
    else
        echo "The HTTP response code was: " $HTTP_response
        break
    fi
done

