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
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);
sub write_file {
    my ($path, $body) = @_;
    open my $file, ">", $path or die "cannot write $path: $!";
    print {$file} $body;
    close $file;
}

write_file("$dir/docker", <<'SH');
#!/usr/bin/env bash
count=$(cat "$KAFKA_TEST_CALLS")
count=$((count + 1))
printf '%s' "$count" > "$KAFKA_TEST_CALLS"
if [ "$count" -le "$KAFKA_TEST_FAILURES" ]; then
    echo 'Replication factor: 1 larger than available brokers: 0.'
    exit 1
fi
SH
write_file("$dir/sleep", "#!/usr/bin/env bash\nexit 0\n");
chmod 0755, "$dir/docker", "$dir/sleep";

for my $script (qw(ci/init-plugin-test-service.sh ci/init-last-test-service.sh)) {
    for my $failures (2, 30) {
        write_file("$dir/calls", "0");
        local $ENV{PATH} = "$dir:$ENV{PATH}";
        local $ENV{KAFKA_TEST_CALLS} = "$dir/calls";
        local $ENV{KAFKA_TEST_FAILURES} = $failures;
        open my $runner, "-|", "bash", "-c",
            'exec 2>&1; source "$1" test; '
            . 'create_kafka_topic kafka zookeeper:2181 1 test2; '
            . 'echo "topic initialization completed"',
            "ci-kafka", $script or die "cannot run $script: $!";
        my $output = do { local $/; <$runner> };
        close $runner;
        my $exit = $? >> 8;
        open my $calls, "<", "$dir/calls" or die "cannot read calls: $!";
        my $count = <$calls>;
        close $calls;
        if ($failures == 2) {
            is($exit, 0, "$script retries until topic creation succeeds") or diag($output);
            is($count, 3, "$script stops retrying after success");
            like($output, qr/topic initialization completed/, "$script continues after success");
        } else {
            is($exit, 1, "$script fails when the broker stays unavailable") or diag($output);
            is($count, 30, "$script bounds topic creation attempts");
            unlike($output, qr/topic initialization completed/,
                "$script does not hide initialization failure behind a later command");
        }
    }
}

done_testing();
