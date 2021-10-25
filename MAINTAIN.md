## Release steps

### Release patch version

1. Create a pull request to minor branch
2. Merge it into minor branch
3. Package a vote artifact to Apache's dev-apisix repo. The artifact can be created
via `VERSION=x.y.z make release-src`
4. Send the vote email to dev@apisix.apache.org
5. When the vote is passed, send the vote result email to dev@apisix.apache.org
6. Move the vote artifact to Apache's apisix repo
7. Create a GitHub release from the minor branch
8. Update APISIX website
9. Update APISIX docker
10. Update APISIX rpm package
11. Send the ANNOUNCE email to dev@apisix.apache.org & announce@apache.org

### Release minor version

1. Create a minor branch, and create pull request to master branch from it
2. Package a vote artifact to Apache's dev-apisix repo. The artifact can be created
via `VERSION=x.y.z make release-src`
3. Send the vote email to dev@apisix.apache.org
4. When the vote is passed, send the vote result email to dev@apisix.apache.org
5. Move the vote artifact to Apache's apisix repo
6. Create a GitHub release from the minor branch
7. Merge the pull request into master branch
8. Update APISIX website
9. Update APISIX docker
10. Update APISIX rpm package
11. Send the ANNOUNCE email to dev@apisix.apache.org & announce@apache.org
