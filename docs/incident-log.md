# Incident log

Real problems hit while building and running this stack, with the symptom, root cause, fix and lesson for each. Nothing here was staged.

## 1. Apply failed: state lock denied

- **Symptom:** `terraform apply` failed with AccessDenied on `s3:PutObject` for `collab/terraform.tfstate.tflock`.
- **Root cause:** The shared apply role's state policy only covered the `dev/` key prefix. With `use_lockfile`, Terraform writes a `.tflock` object next to the state file.
- **Fix:** Added a name-scoped policy (`platform-apply-state-collab`) allowing Get/Put/Delete on the collab state key and its `.tflock`, plus `ListBucket` on that prefix.
- **Lesson:** S3-native locking needs write and delete on the lock object, not just the state file. Scope by key, never by bucket.

## 2. Nextcloud 502 on first start; task killed mid-install

- **Symptom:** ALB returned 502, targets unhealthy. The log showed "Another process is initializing Nextcloud. Waiting..." after a restart.
- **Root cause:** The whole `/var/www/html` was on EFS. On first start the image copies its entire code tree there. Thousands of small files on EFS took over 10 minutes, the health-check grace period expired, and ECS killed the task mid-copy. That left a stale `nextcloud-init-sync.lock` which blocked every later start.
- **Fix:** Persist only state: three EFS access points (`data`, `config`, `custom_apps`, uid/gid 33) mounted over those paths. Code stays on the container's local disk. First-start initialisation dropped to about 23 seconds.
- **Lesson:** Persist state, not code. EFS is poor at many small files. Access points give each path its own owner and root.

## 3. Plan failed: state read denied (HeadObject 403)

- **Symptom:** The PR plan failed on `HeadObject` with 403.
- **Root cause:** The read-only plan role had no access to the collab state key. S3 returns 403, not 404, when the caller cannot read the object.
- **Fix:** Added `platform-plan-state-collab` (read on the state key, list on the prefix).
- **Lesson:** A 403 on a state file can mean "exists but unreadable", so don't assume it is missing.

## 4. Plan failed: EFS describe denied

- **Symptom:** Plan failed with 403 on `DescribeFileSystems`.
- **Root cause:** The plan role had no EFS read permissions, and refresh needs them.
- **Fix:** Added `platform-plan-efs` (read-only `elasticfilesystem:Describe*`).
- **Lesson:** Every new resource type needs read actions on the plan role as well as write actions on the apply role.

## 5. ECS replace loop: health check returned 400

- **Symptom:** ECS replaced the task about every 16 minutes. Service events: "unhealthy ... Health checks failed with these codes: [400]".
- **Root cause:** The ALB probes `/status.php` by the container's private IP. Before installation Nextcloud answered any host. After installation it only accepts hosts in `trusted_domains`, so probes got 400. The target was healthy during setup and failed once the grace period ended.
- **Fix:** Target group matcher changed from `200` to `200,400`.
- **Trade-off:** A 400 still proves Apache, PHP and the EFS config are working, but it is a weaker check. Next step would be a custom image with a dedicated health endpoint, or a sidecar.
- **Lesson:** Health checks that depend on the Host header break behind a load balancer.

## Persistence test

Stopped the running task on purpose (`aws ecs stop-task`). ECS started a replacement with a fresh container. Result: target healthy within about 2 minutes, admin login worked, the uploaded file was still present, and the start-up log showed a clean initialisation. Note: the image prints "New nextcloud instance" on every fresh container, because `version.php` lives on local disk. That message does not mean data loss.

## Design trade-offs

- **No internet from private subnets:** the Nextcloud App Store is unreachable ("Could not fetch list of apps"). The image is mirrored into ECR and pinned by digest because Docker Hub is unreachable too.
- **HTTP only:** HTTPS needs a domain and a certificate. Listed as a stretch goal.
- **Database name:** `inventory` comes from the shared database module.
- **Admin account:** created in the browser, so the password never touches code or state.
