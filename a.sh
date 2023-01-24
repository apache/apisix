#!/bin/bash

all_tags="redis:latest 122 34234 test-body-image test-uri-image"
to_pull=""
          for tag in $all_tags
          do
          if ! ( docker inspect $tag )
          then
          # echo $? : $tag
          to_pull="${to_pull} ${tag}"
          fi
          done

echo $to_pull