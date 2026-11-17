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

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

sub check_result {
    my ($name, $log, $expected) = @_;
    my ($file, $path) = tempfile(UNLINK => 1);
    print {$file} $log;
    close $file;

    open my $runner, "-|", "bash", "-c",
        'exec 2>&1; source ci/common.sh; set +x; '
        . 'fail_on_bailout "$1"; rerun_flaky_tests "$1"',
        "ci-bailout", $path or die "cannot run CI result checks: $!";
    my $output = do { local $/; <$runner> };
    close $runner;
    is($? >> 8, $expected, $name) or diag($output);
}

check_result("a completed passing suite succeeds", "Result: PASS\n", 0);
check_result("bailout overrides a passing summary",
    "Bailout called.  Further testing stopped: nginx failed to start\n"
    . "All tests successful.\nResult: PASS\n", 1);
check_result("a bailed-out failing suite is not retried as a partial suite",
    "Bailout called.  Further testing stopped: nginx failed to start\n"
    . "Result: FAIL\n", 1);

done_testing();
