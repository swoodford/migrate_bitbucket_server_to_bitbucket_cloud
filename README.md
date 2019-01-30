<h1 align="center"><img src="/images/migrate_bitbucket_server_to_bitbucket_cloud.png" alt="Migrate Atlassian Bitbucket Server to Bitbucket Cloud" width=500 height=342></h1>

<h2 align="center">Migrate Atlassian Bitbucket Server to Bitbucket Cloud</h2>

[![Build Status](https://travis-ci.org/swoodford/migrate_bitbucket_server_to_bitbucket_cloud.svg?branch=master)](https://travis-ci.org/swoodford/migrate_bitbucket_server_to_bitbucket_cloud)

[https://github.com/swoodford/migrate_bitbucket_server_to_bitbucket_cloud](https://github.com/swoodford/migrate_bitbucket_server_to_bitbucket_cloud)


**Requirements:**  
It is recommended to run this script as `root` directly on your Bitbucket Server (Linux only)  
Requires `curl, git, jq, bc, openssl`  
Run `install_requirements.sh` to install these packages  
The migration script may work on Mac OS but this has not been tested so run at your own risk!  


#### TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION:
YOU MUST AGREE TO ALL TERMS IN [APACHE LICENSE 2.0](https://github.com/swoodford/migrate_bitbucket_server_to_bitbucket_cloud/blob/master/LICENSE.md)  
THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND  
YOU AGREE TO ACCEPT ALL LIABILITY IN USING THIS WORK AND ASSUME ANY AND ALL RISKS ASSOCIATED WITH RUNNING THIS WORK  


### Steps for use:

1. Create Bitbucket Cloud Account and Setup Team
2. Create OAuth Consumer in Bitbucket Cloud with Full Permisions to Team Account
3. Create Admin or System Admin level user for migration on your Bitbucket Server
4. Set all required variables in the script [migrate.sh](migrate.sh) then run `./migrate.sh`


### Migration process works in the following way:

1. Get list of all Projects and Repos from Bitbucket Server
2. Create new Project in Bitbucket Cloud
3. Create new Repo in Cloud
4. Backup each Project Repo and all branches locally using git
5. Add new git remote cloud, push all branches to cloud
6. Send email to git committers when each repo is migrated (optional)

#### Or migration can be done in phases with specific projects and repos (see notes in script)  

### Post migration:
1. Update many local machine git repo URLs to Bitbucket Cloud URLs by running [update-git-repo-urls.sh](update-git-repo-urls.sh)


## Bugs and feature requests
Have a bug or a feature request? The [issue tracker](https://github.com/swoodford/migrate_bitbucket_server_to_bitbucket_cloud/issues) is the preferred channel for bug reports, feature requests and submitting pull requests.
If your problem or idea is not addressed yet, [please open a new issue](https://github.com/swoodford/migrate_bitbucket_server_to_bitbucket_cloud/issues/new).

## Creator

**Shawn Woodford**

- <https://shawnwoodford.com>
- <https://github.com/swoodford>

## Copyright and License

Code and Documentation Copyright 2018 Shawn Woodford. 
Code released under the [Apache License 2.0](https://github.com/swoodford/migrate_bitbucket_server_to_bitbucket_cloud/blob/master/LICENSE.md).
