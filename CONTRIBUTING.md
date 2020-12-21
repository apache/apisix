<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

# Contributing to APISIX

Firstly, thanks for your interest in contributing! I hope that this will be a
pleasant first experience for you, and that you will return to continue
contributing.

## How to contribute?

Most of the contributions that we receive are code contributions, but you can
also contribute to the documentation or simply report solid bugs
for us to fix.

 For new contributors, please take a look at issues with a tag called [Good first issue](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) or [Help wanted](https://github.com/apache/apisix/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).

## How to report a bug?

* **Ensure the bug was not already reported** by searching on GitHub under [Issues](https://github.com/apache/apisix/issues).

* If you're unable to find an open issue addressing the problem, [open a new one](https://github.com/apache/apisix/issues/new). Be sure to include a **title and clear description**, as much relevant information as possible, and a **code sample** or an **executable test case** demonstrating the expected behavior that is not occurring.

## How to add a new feature or change an existing one

_Before making any significant changes, please [open an issue](https://github.com/apache/apisix/issues)._ Discussing your proposed changes ahead of time will make the contribution process smooth for everyone.

Once we've discussed your changes and you've got your code ready, make sure that tests are passing and open your pull request. Your PR is most likely to be accepted if it:

* Update the README.md with details of changes to the interface.
* Includes tests for new functionality.
* References the original issue in the description, e.g. "Resolves #123".
* Has a [good commit message](http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html).
* Ensure your pull request's title starts from one of the word in the `types` section of [semantic.yml](https://github.com/apache/apisix/blob/master/.github/semantic.yml).

## Contribution Guidelines for Documentation

* Linting/Style

    Use a markdown linting tool to lint the content. The following is a [plugin](https://github.com/apache/apisix/issues/1273)
    used by our community to lint the docs.

* Active Voice

    In general, use active voice when formulating the sentence instead of passive voice. A sentence written in the active voice will emphasize
    the person or thing who is performing an action (eg.The dog chased the ball).  In contrast, the passive voice will highlight
    the recipient of the action (The ball was chased by the dog). Therefore use the passive voice, only when it's less important
    who or what completed the action and more important that the action was completed. For example:

    - Recommended: The key-auth plugin authenticates the requests.
    - Not recommended: The requests are authenticated by the key-auth plugin.

* Capitalization:

    * For titles of a section, capitalize the first letter of each word except for the [closed-class words](https://en.wikipedia.org/wiki/Part_of_speech#Open_and_closed_classes)
      such as determiners, pronouns, conjunctions, and prepositions. Use the following [link](https://capitalizemytitle.com/#Chicago) for guidance.
      - Recommended: Authentication **with** APISIX

    * For normal sentences, don't [capitalize](https://www.grammarly.com/blog/capitalization-rules/) random words in the middle of the sentences.
      Use the Chicago manual for capitalization rules for the documentation.

* Second Person

    In general, use second person in your docs rather than first person. For example:

    - Recommended: You are recommended to use the docker based deployment.
    - Not Recommended: We recommend to use the docker based deployment.

* Spellings

    Use [American spellings](https://www.oxfordinternationalenglish.com/differences-in-british-and-american-spelling/) when
    contributing to the documentation.

* Voice

    * Use a friendly and conversational tone. Always use simple sentences. If the sentence is lengthy try to break it in to smaller sentences.

## Check code style and test case style

* code style
    * Please take a look at [APISIX Lua Coding Style Guide](CODE_STYLE.md).
    * Use tool to check your code statically by command: `make lint`.
```shell
        # install `luacheck` first before run it
        $ luarocks install luacheck
        # check source code
        $ make lint
        luacheck -q lua
        Total: 0 warnings / 0 errors in 74 files
        ./utils/lj-releng \
            apisix/*.lua \
            apisix/admin/*.lua \
            apisix/core/*.lua \
            apisix/http/*.lua \
            apisix/http/router/*.lua \
            apisix/plugins/*.lua \
            apisix/plugins/grpc-transcode/*.lua \
            apisix/plugins/limit-count/*.lua > \
            /tmp/check.log 2>&1 || (cat /tmp/check.log && exit 1)
```
      The `lj-releng` will be downloaded automatically by `make lint` if not exists.

* test case style
    * Use tool to check your test case style statically by command, eg: `reindex t/admin/*.t`.
```shell
    # install `reindex` first before run it
    # wget https://raw.githubusercontent.com/iresty/openresty-devel-utils/master/reindex
    # ./reindex test cases
    $ reindex t/admin/*.t
    reindex: t/plugin/example.t:	skipped.        # No changes needed
    reindex: t/plugin/fault-injection.t:	done.   # updated
    reindex: t/plugin/grpc-transcode.t:	skipped.
    ... ...
    reindex: t/plugin/udp-logger.t:	done.
    reindex: t/plugin/zipkin.t:	skipped.
```
    * By the way, we can download "reindex" to another path and add this path to "PATH" environment.
    * When the test file is too large, for example > 800 lines, you should split it to a new file.
      Please take a look at `t/plugin/limit-conn.t` and `t/plugin/limit-conn2.t`.

## Do you have questions about the source code?

- **QQ Group**: 578997126(recommended), 552030619
- Join in `apisix` channel at [Apache Slack](http://s.apache.org/slack-invite). If the link is not working, find the latest one at [Apache INFRA WIKI](https://cwiki.apache.org/confluence/display/INFRA/Slack+Guest+Invites).
