# Add UAA Users

A script that can easily batch-add a bunch of users to
a UAA server. Simply fill out or edit the configuration
file and point the script at it.

## Installation

Clone the repository and navigate to the adduaausers
directory. Run the `install` script found within, you will need `sudo` access. That script will build all of the dependencies located in the
`vendor` directory. Note that this has a dependency on
the `luarocks` utility. `apt-get` it if necessary.

## Usage

A description of the command line syntax and valid flags
can be seen by running the help command
(`./adduaausers help`). By default, the config is taken
from stdin and the updated config is given at stdout.
All logging is done on stderr.

### Commands:
`cf`: add users with admins configured for Cloud Foundry  
`uaa`: add users with admins configured for the UAA itself  
`bosh`: add users with admins configured for BOSH  
`password`: stop after generating passwords  
`nopass`: output a config with all passwords removed  
`remove`: removes all users in the config from the UAA

### Flags:
`-i`, `--inplace`: Outputs the new config to the input file
as specified by `-f` instead of stdout. Invalid if `-f` is
not given.  
`-f`, `--filename`: Specifies a file to use as config
instead of stdin.

### Syntax:  
`adduaausers <command> <flags...>`

## Configuration
```yaml
config:
  password: #password restrictions when generating passwords.
            # optional. all within also optional
    min_length: #minimum password length.
    digits: #digits required
    lower_case: #lower case characters required
    special: #special characters required
    upper_case: #uppercase characters requierd
    max_length: #maximum password length
  uaa:
    target: #protocol://host:port/endpoint of UAA to target.
    client_secret: #client secret given to UAA on deployment
    skipssl: #boolean for skipping ssl validation to UAA
admins: #array of usernames to make admin
- #string corresponding to "name" key in the "users" array

users: #array of users to create, if necessary
- password: #password for this user
  name: #the name given to the user in the UAA
  email: #email associated with this user for the UAA
```

An example of the config file is in `users.yml`.  Using a copy of this file on the site1 prod jumpbox:
```
lua adduaausers.lua bosh -f users.yml -i
```

## Using wrapper.lua
The config files are split per-environment in a Genesis-like way (the way we do our deployment repos). A wrapper script was made for the main script to spruce up the correct files and run the program to add users.  

Usage looks like:  
`wrapper.lua cf site1/sandbox`  

In that example, `cf` could instead be `bosh`, and `site1/sandbox` could be `site2/prod` or any other environment in the environment files.
You can also specify an additional `remove` option to delete all the users specified in the config from the UAA.

i.e. `wrapper.lua remove cf site1/sandbox`
