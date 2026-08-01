# PR Tracking

| Issue | Branch | PR | Status | Created (UTC) | Testing | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| #10787 | `auto/issue-10787` | TBD | In progress | TBD | `git diff` reviewed; `grep -RInE 'grpc-transcode\|gRPC\|HTTP upstream\|HTTP 上游\|gRPC 转码' docs/en/latest/plugins/ext-plugin-post-resp.md docs/zh/latest/plugins/ext-plugin-post-resp.md` confirmed English and Chinese limitation text. Full docs lint not run yet (documentation-only minimal change; no docs lint environment discovered/run before PR creation). | Clarifies `ext-plugin-post-resp` only works with HTTP upstreams / HTTP response flow and should not be used with `grpc-transcode` or non-HTTP upstream response flows. |
| N/A | `fix/issue-...` | https://github.com/apache/apisix/pull/13390 | Review required; PR lint success | 2026-05-19 11:52 | PR lint success | Existing open PR. Not pinged this round because it has been less than 24 hours since creation, and an explanatory comment was already added on 2026-05-20 03:08 UTC. |
