# Contributing

## Code of Conduct

Help us keep vue-typescript-admin-template open and inclusive. Please read and follow the [Code of Conduct](https://github.com/Armour/vue-typescript-admin-template/blob/master/.github/CODE_OF_CONDUCT.md).

## Found a Bug

If you find a bug in the source code, you can help us by [submitting an issue](#submitting-an-issue) to our [GitHub Repository](https://github.com/Armour/vue-typescript-admin-template). Even better, you can [submit a Pull Request](#submitting-a-pull-request) with a fix.

## Missing a Feature

You can *request* a new feature by [submitting an issue](#submitting-an-issue) to our GitHub Repository. If you would like to *implement* a new feature, please submit an issue with a proposal for your work first, to be sure that we can use it. Please consider what kind of change it is:

* For a **Major Feature**, first open an issue and outline your proposal so that it can be discussed. This will also allow us to better coordinate our efforts, prevent duplication of work, and help you to craft the change so that it is successfully accepted into the project.

* **Small Features** can be crafted and directly [submitted as a Pull Request](#submitting-a-pull-request).

## Submission Guidelines

### Submitting an Issue

Before you submit an issue, please search the issue tracker, maybe an issue for your problem already exists and the discussion might inform you of workarounds readily available.

We want to fix all the issues as soon as possible, but before fixing a bug we need to reproduce and confirm it. In order to reproduce bugs, we will systematically ask you to provide a minimal reproduction scenario. Having a live, reproducible scenario gives us a wealth of important information without going back & forth to you with additional questions.

We will be insisting on a minimal reproduce scenario in order to save maintainers time and ultimately be able to fix more bugs. Interestingly, from our experience users often find coding problems themselves while preparing a minimal plunk. We understand that sometimes it might be hard to extract essentials bits of code from a larger code-base but we really need to isolate the problem before we can fix it.

Unfortunately, we are not able to investigate / fix bugs without a minimal reproduction, so if we don't hear back from you we are going to close an issue that doesn't have enough info to be reproduced.

You can file new issues by filling out the [new issue form](https://github.com/Armour/vue-typescript-admin-template/issues/new).

### Submitting a Pull Request

Before you submit your Pull Request (PR) consider the following guidelines:

1. Search [GitHub](https://github.com/Armour/vue-typescript-admin-template/pulls) for an open or closed PR that relates to your submission. You don't want to duplicate effort.

1. Fork this repo.

1. Make your changes in a new git branch.

    ```shell
    git checkout -b my-new-feature master
    ```

1. Commit your changes using a descriptive commit message that follows our [commit message convention](#commit-message-convention). Adherence to these conventions is necessary because release notes are automatically generated from these messages.

    ```shell
    git commit -am 'Add some feature'
    ```

1. Push your branch.

    ```shell
    git push origin my-new-feature
    ```

1. Send a pull request :D

That's it! Thank you for your contribution!

#### After your pull request is merged

After your pull request is merged, you can safely delete your branch and pull the changes
from the main (upstream) repository:

* Delete the remote branch on GitHub either through the GitHub web UI or your local shell as follows:

    ```shell
    git push origin --delete my-new-feature
    ```

* Check out the master branch:

    ```shell
    git checkout master -f
    ```

* Delete the local branch:

    ```shell
    git branch -D my-new-feature
    ```

* Update your master with the latest upstream version:

    ```shell
    git pull
    ```

## Commit Message Convention

We have very precise rules over how our git commit messages can be formatted.  This leads to **more readable messages** that are easy to follow when looking through the **project history**.  But also, we use the git commit messages to **generate the change log**.

Please read and follow the [Commit Message Format](https://github.com/Armour/vue-typescript-admin-template/blob/master/.github/COMMIT_CONVENTION.md).
