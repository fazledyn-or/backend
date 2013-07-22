#!/bin/bash
#
# Update Perl module dependencies to their latest versions.
#
# This script removes carton.lock, Carton's cache and modules themselves so Carton is then
# forced to check for new versions of modules.
#

if [ ! -f cpanfile ]; then
    echo "Run this script from the root of the Media Cloud repository."
    exit 1
fi

# Update Carton
source ./script/set_perl_brew_environment.sh
cpanm Carton

# Remove modules and Carton's cache, then reinstall the modules
rm -rf .carton/
rm -rf local/
rm carton.lock
./script/run_carton.sh install  # running with "--deployment" would not regenerate carton.lock

# Add new carton.lock to SCM
if [ -d .git ]; then
    git add carton.lock
fi