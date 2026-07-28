# External Logging Installer — troubleshooting

This installer deploys a Graylog stack on a virtual machine with Ansible: Graylog, OpenSearch, and MongoDB as Docker
containers, fronted by nginx and optionally Keepalived, with FluentD or FluentBit collecting the VM's own container
logs. Find the symptom below, then read its section.

The roles create the containers `graylog_graylog_1`, `graylog_storage_1` (OpenSearch), `graylog_mongo_1`,
`graylog_web_1` (nginx), and `graylog_fluentd_1` or `graylog_fluentbit_1`.

Cluster-side FluentD and FluentBit — the DaemonSets that ship application logs from Kubernetes into this Graylog — are
deployed by the qubership-logging-operator, not by this installer. Their failures belong to that repository's
troubleshooting guide. The FluentD and FluentBit sections here cover only the agent this installer runs on the Graylog
VM.

## Ansible

### Ansible run fails on SSH authentication

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
UNREACHABLE! => {"msg": "Failed to connect to the host via ssh: ... Permission denied (publickey,password)"}
```
<!-- markdownlint-enable line-length -->

* A manual `ssh` to the same host succeeds, but Ansible still reports an authentication failure.
* The `-vvvv` output shows the offered key rejected, or a fallback to a password prompt.

**Root cause:**

1. The control node's public key is missing from the target user's `~/.ssh/authorized_keys`, or the key path in
   `ansible_ssh_private_key_file` is wrong.
2. Host key checking is enabled by default, and the target's host key changed or is unknown, so the connection is
   refused before authentication is attempted.
3. The inventory names the wrong `ansible_user`, or the control node's SSH agent does not hold the expected key.

**How to check:**

1. Read the exact SSH error in the `-vvvv` output. A rejected key and an unknown host key fail differently.
2. Compare the `ansible_user`, `ansible_host`, and `ansible_ssh_private_key_file` values for the failing host against
   the target.
3. Run `ssh -i <keyfile> <user>@<host>` from the control node. Success here with a failure in Ansible points at the
   inventory, not at the target.

**How to fix:**

1. Correct the inventory variables for the affected host.
2. Add the control node's public key to the target's `authorized_keys`.
3. If host key checking is the blocker, refresh the relevant `known_hosts` entry. Do not disable the check to work
   around a changed host key — that suppresses a real warning.

**Data to collect:**

* The full `-vvvv` output for one failing host.
* The host's inventory group and host variables.
* The result of `ssh -i <keyfile> <user>@<host>` from the control node.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Connection methods and details — Ansible Community Documentation](https://docs.ansible.com/projects/ansible/latest/inventory_guide/connection_details.html)
<!-- markdownlint-enable line-length -->

### Ansible run fails during privilege escalation

**Symptoms:**

* The playbook connects, then hangs and times out at a become password prompt.
* A task fails with `Missing sudo password` or `sudo: a password is required`.

**Root cause:**

1. The become user requires a sudo password, but Ansible was not given one — no `-K`, no configured become password.
2. `become_method` or `become_user` does not match what the target has installed.
3. The become user has no `NOPASSWD` sudoers entry and the run is unattended, so no password can be supplied
   interactively.

**How to check:**

1. Read whether the output shows a hang at a password prompt or an explicit sudoers denial. These have different fixes.
2. Check the `become`, `become_method`, and `become_user` settings in effect for the play or task.
3. Check the target's sudoers configuration for the become user.

**How to fix:**

1. For an interactive run, supply the become password with `-K`.
2. For an unattended run, configure a vault-stored `ansible_become_password`, or add a `NOPASSWD` sudoers entry for the
   become user.
3. Align `become_method` with what the target host actually has installed.

**Data to collect:**

* The task output showing the failure or the hang.
* The play and task `become` settings.
* The target's sudoers entry for the become user.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Understanding privilege escalation: become — Ansible Community Documentation](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_privilege_escalation.html)
<!-- markdownlint-enable line-length -->

### Ansible re-run does not finish after a partial install

**Symptoms:**

* A task fails partway through the install run — a missing package, a port already in use, or insufficient disk space.
* A second run of the same playbook still fails, sometimes on a different task.

**Root cause:**

1. A prerequisite the role assumes — a package, a free port, free disk space — was not met, so the task fails with a
   generic error rather than an actionable one.
2. A partially applied change from the failed run left the host in a state later tasks do not account for.
3. `ignore_errors` was applied broadly, hiding the visible failure without fixing the unmet prerequisite, so the next
   task that needs it fails instead.

**How to check:**

1. Find the task name and error message from the *first* failing run, not the second. The second failure is often a
   consequence of the first.
2. Check free disk space (`df -h`) and listening ports (`ss -ltnp`) on the affected host.
3. Check whether `ignore_errors` or `failed_when` on nearby tasks is masking the real failure.

**How to fix:**

1. Fix the specific unmet prerequisite on the affected host — install the package, free the port, free disk space.
2. Re-run the full playbook. Ansible modules are idempotent, so a clean re-run applies only what is still outstanding.

**Data to collect:**

* The full task output and return code from the first failure.
* `df -h` and `ss -ltnp` from the target host.
* The name of the role and task that failed.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Error handling in playbooks — Ansible Community Documentation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_error_handling.html)
<!-- markdownlint-enable line-length -->

### Ansible install fails on an undefined variable

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
fatal: [host]: FAILED! => {"msg": "Could not find or access 'vars/prod.yml'..."}
AnsibleUndefinedVariable: 'dict object' has no attribute 'merge_params'
AnsibleUndefinedVariable: 'ssl_data_host_path_exporter' is undefined
```
<!-- markdownlint-enable line-length -->

* The failure appears only in one environment, or only when an optional flag such as
  `proxy_exporter_https_enable: true` is set. The same install succeeds with the flag at its default.
* An earlier task in the same play logged `...ignoring` shortly before the error.

**Root cause:**

1. The `include_vars` or `vars_files` path does not exist for this host's environment or group — commonly a new
   environment that never got its own vars file.
2. An earlier task that was supposed to set the variable failed, but `ignore_errors: true` or `failed_when: false` hid
   it, so a later task references a variable that was never set.
3. `defaults/main.yml` defines the base variable but not the variant a conditional task references once an optional
   flag is enabled, and the environment that enabled the flag never defined the companion variable itself.
4. A typo in the variable name or file path points Ansible at the wrong file or key.

**How to check:**

1. Compare the `include_vars`/`vars_files` path in the task output against the directory layout on disk.
2. Look for an earlier task in the same play that logged `...ignoring` before the error. That masked failure is the
   real one.
3. Look for the variable named in the error in the role's `defaults/main.yml`. Absence there, combined with a `when:`
   on an optional flag in the task that uses it, confirms the flag-gated case.
4. Check whether the flag is set to `true` only in the failing environment.

**How to fix:**

1. Create the missing vars file for the affected environment or group, or correct the path.
2. If an earlier failure was being ignored, remove the blanket `ignore_errors`/`failed_when` and fix that failure.
   Suppressing it only moves the error later.
3. For a flag-gated variable, set it explicitly in the environment's `group_vars`/`host_vars` for as long as the flag
   is enabled, and add a default in `defaults/main.yml` so enabling the flag alone is sufficient.

**Data to collect:**

* The full task output for the failing task, and for any earlier task that logged `...ignoring`.
* A directory listing of the expected vars path.
* The role's `defaults/main.yml` and the task definition referencing the undefined variable.
* The flag's value across every inventory group, if a flag is involved.

**Sources:**

<!-- markdownlint-disable line-length -->
* [include_vars module — Ansible Community Documentation](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/include_vars_module.html)
* [Working With Playbooks: Variables — Ansible Community Documentation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html)
* [Roles: reusable files, tasks, handlers, and other Ansible artifacts — Ansible Community Documentation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
<!-- markdownlint-enable line-length -->

## Graylog

### Graylog install aborts on unsupported OS or Python

**Symptoms:**

```text
fatal: [host]: FAILED! => {"msg": "Fail if OS is not CentOS or RHEL"}
```

* Or `'dict object' has no attribute 'distribution'`, or a missing-interpreter error, when Ansible cannot locate Python
  on the host.

**Root cause:**

1. The role's OS-support guard — an `assert` or `fail` task keyed on `ansible_facts['distribution']` — rejects a target
   OS this installer never supported.
2. The target has Python 3 only at a non-default path, and interpreter auto-discovery falls back to a `/usr/bin/python`
   that does not exist, so fact gathering fails before the OS guard runs.
3. `ansible_python_interpreter` is pinned in the inventory to a path that does not exist on this host, so every
   fact-dependent task fails, including the OS check.

**How to check:**

1. Read the fail or assert task name and message from the output.
2. Compare `ansible_facts['distribution']` and `ansible_distribution_major_version` on the target against the role's
   supported-OS list.
3. Check whether `ansible_python_interpreter` is set in the inventory, and whether that path exists on the failing host.

**How to fix:**

1. Run the install against a supported OS. Do not bypass the guard — the roles were never validated elsewhere.
2. For an interpreter failure, install a supported Python 3 and set `ansible_python_interpreter` to its real path, or
   to `auto`.

**Data to collect:**

* The failing task's full output.
* `cat /etc/os-release` and `which python3` from the target.
* The inventory value of `ansible_python_interpreter` for that host.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Conditionals — Ansible Community Documentation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
* [Interpreter Discovery — Ansible Community Documentation](https://docs.ansible.com/ansible/latest/reference_appendices/interpreter_discovery.html)
<!-- markdownlint-enable line-length -->

### Unable to connect to Graylog via browser

**Symptoms:**

* The Graylog web UI does not open in a browser.

**Root cause:**

One of the stack's containers is not running, or the VM itself is unreachable over the network.

**How to check:**

1. Connect to the Graylog VM over SSH. If SSH itself fails, check the network connection with `ping` — the problem is
   below Graylog.
2. Show the container status:

   ```bash
   docker ps -f "name=graylog"
   ```

   A healthy VM lists `graylog_web_1`, `graylog_graylog_1`, `graylog_storage_1`, and `graylog_mongo_1`, each with a
   `STATUS` of `Up N days`.

3. If a container is missing or its status differs, that container is the problem.

**How to fix:**

1. Restart the container that is not up.
2. If it does not stay up, read its log and follow the case for that component. A restarting `graylog_storage_1` or
   `graylog_mongo_1` usually means disk or memory — see [HDD full on the Graylog VM](#hdd-full-on-the-graylog-vm) and
   [Graylog container OOM killed](#graylog-container-oom-killed).
3. If `graylog_web_1` is up but the UI still returns an error, see
   [Graylog web UI returns 502 behind nginx](#graylog-web-ui-returns-502-behind-nginx).

**Data to collect:**

* `docker ps -f "name=graylog"` output.
* The log of the container that is not up.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### No log messages arrive in Graylog

**Symptoms:**

* Searches return no recent messages, though Graylog itself is up.

**Root cause:**

Either Graylog is failing to accept or index what it receives, or nothing is being sent to it.

**How to check:**

1. Open **System > Overview** in the web UI and read the reported errors.
2. Open **System > Inputs** and check whether the input is running and its message count is increasing.
3. If the input receives nothing, the sender is at fault. Check the VM agent — `graylog_fluentd_1` or
   `graylog_fluentbit_1` — and, for logs shipped from Kubernetes, the cluster-side agent deployed by the
   qubership-logging-operator.

**How to fix:**

1. Fix the errors reported on the Overview page. An indexer failure there means the logs arrive but cannot be stored —
   see [Graylog not processing messages](#graylog-not-processing-messages).
2. If the input counter is flat, the problem is on the sending side. For the VM agent, see
   [FluentD worker is killed with SIGKILL](#fluentd-worker-is-killed-with-sigkill) or
   [FluentBit cannot deliver logs to Graylog](#fluentbit-cannot-deliver-logs-to-graylog).

**Data to collect:**

* The **System > Overview** errors.
* The input's message counters from **System > Inputs**.
* The sending agent's log for the same window.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Graylog fails to connect to OpenSearch

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
Couldn't read cluster health for indices
Could not connect to <opensearch_host>:9200
```
<!-- markdownlint-enable line-length -->

* The web UI reports the indexer or cluster as unavailable.
* Message processing stalls while the journal grows.

**Root cause:**

1. `elasticsearch_hosts` in `server.conf` does not point to a reachable OpenSearch node — wrong host, port, or scheme —
   or the credentials embedded in the URI are wrong.
2. OpenSearch is down, still starting, or has not finished forming its cluster.
3. A firewall blocks the configured HTTP port, commonly 9200, between the Graylog and OpenSearch hosts.
4. The client returning `401 Unauthorized` is `elasticsearch_exporter`, not Graylog. It queries OpenSearch on its own
   through the `--es.uri` flag in `roles/opensearch_exporter/templates/elasticsearch_exporter.service.jinja`, so a
   credentials mismatch there fails independently of `elasticsearch_hosts`.

**How to check:**

1. Compare the `elasticsearch_hosts` value in `server.conf` against the actual OpenSearch node address and port.
2. Run `curl` from the Graylog host to that address and port.
3. Read OpenSearch's own log and `_cluster/health` output on the OpenSearch node.
4. Check whether an HTTP 401 in the log comes from `elasticsearch_exporter` rather than from Graylog. The two use
   separate credentials.

**How to fix:**

1. Correct `elasticsearch_hosts` to a reachable node with valid credentials.
2. Open the required port between the hosts.
3. Resolve any OpenSearch-side cluster-formation problem first — see
   [OpenSearch cluster status is red or yellow](#opensearch-cluster-status-is-red-or-yellow). Graylog cannot reconnect
   to a cluster that has not formed.
4. If `elasticsearch_exporter` is the failing client, correct the credentials in its `--es.uri` flag so they match the
   OpenSearch user it authenticates as.

**Data to collect:**

* The `elasticsearch_hosts` setting, with credentials redacted.
* The Graylog server log around the connection failure.
* `curl` output from the Graylog host to the OpenSearch HTTP port.

**Sources:**

<!-- markdownlint-disable line-length -->
* [OpenSearch — Graylog documentation](https://go2docs.graylog.org/current/setting_up_graylog/opensearch.htm)
<!-- markdownlint-enable line-length -->

### Graylog fails to connect to MongoDB

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
Unable to connect to MongoDB. Is it running and the configuration correct?
Command failed with error 18 (AuthenticationFailed)
```
<!-- markdownlint-enable line-length -->

* Graylog fails to start, or the log shows a socket or connection exception against MongoDB.

**Root cause:**

1. `mongodb_uri` in `server.conf` has the wrong host, port, credentials, or `authSource`, so MongoDB rejects the
   connection.
2. MongoDB is not running, or is bound to an address or port the Graylog host cannot reach.
3. For a replica set, `mongodb_uri` does not list every member or omits `replicaSet=<name>`, so Graylog cannot find a
   primary.
4. The client failing authentication is `mongodb_exporter`, not Graylog. It opens its own connection through the
   `--mongodb.uri` flag in `roles/mongodb_exporter/tasks/deploy_mongodb_exporter.yaml`, so `AuthenticationFailed` and
   SCRAM errors can come from its credentials rather than from `mongodb_uri`.

**How to check:**

1. Compare the `mongodb_uri` value in `server.conf`, with the password redacted, against the actual MongoDB host, port,
   and authentication database.
2. Authenticate from the Graylog host with a MongoDB shell using the same credentials.
3. Read MongoDB's own log for the rejected connection attempt.
4. Check whether the process reporting the failure is Graylog or `mongodb_exporter`.

**How to fix:**

1. Correct `mongodb_uri` — host, port, credentials, `authSource`, and, for a replica set, `replicaSet=<name>` with
   every member listed.
2. Confirm MongoDB is running and reachable on the expected port. If it is not, see
   [MongoDB fails to start](#mongodb-fails-to-start).
3. Recreate the Graylog database user if its credentials were rotated.
4. If `mongodb_exporter` is the failing client, correct the credentials in its `--mongodb.uri` flag.

**Data to collect:**

* The `mongodb_uri` setting, with credentials redacted.
* The Graylog startup log.
* The MongoDB log around the same timestamp.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Graylog Server Configuration Settings Reference — Graylog documentation](https://go2docs.graylog.org/current/setting_up_graylog/server_configuration_settings_reference.htm)
* [Authentication on Self-Managed Deployments — MongoDB Docs](https://www.mongodb.com/docs/manual/core/authentication/)
<!-- markdownlint-enable line-length -->

### HDD full on the Graylog VM

**Symptoms:**

* Graylog does not process any new messages.
* Searching logs shows various errors, for example HTTP 500.
* OpenSearch is down and its container restarts constantly.

**Root cause:**

The VM's disk is full, so OpenSearch cannot write. Index rotation is not keeping total index size within the available
disk.

**How to check:**

1. Log in to the Graylog VM over SSH and run `df -h`. It reports disk utilization.

**How to fix:**

1. Log in to the Graylog VM over SSH as root.
2. **DANGEROUS — destroys every log stored on this VM, and stops the whole stack while it runs.** Stop the containers,
   remove the OpenSearch node data, and start them again. Restore the logs from a backup afterward if you need them;
   without a backup they are gone.

   ```bash
   docker stop \
        graylog_web_1 \
        graylog_graylog_1 \
        graylog_storage_1 \
        graylog_mongo_1

   rm -rf /srv/docker/graylog/opensearch/nodes/

   docker start \
         graylog_mongo_1 \
         graylog_storage_1 \
         graylog_graylog_1 \
         graylog_web_1
   ```

3. **DANGEROUS — removes OpenSearch's own disk-full protection.** If the web UI still shows `index read-only` warnings
   after the cleanup, unlock the indices. Only do this once `df -h` confirms the disk is actually below 90%: clearing
   the flag on a still-full disk lets OpenSearch write until it fills the disk again.

   ```bash
   curl -X PUT -u <username>:<password> -H "Content-Type: application/json" \
     -d '{"index.blocks.read_only_allow_delete": null}' http://localhost:9200/_settings
   ```

   See [Index read-only warnings](#index-read-only-warnings) for the full treatment and for why the block returns if
   rotation stays unchanged.

**How to avoid this issue:**

Adjust the index rotation policy in Graylog to the available disk size. See
[Index read-only warnings](#index-read-only-warnings) for the sizing rule.

**Data to collect:**

* `df -h` from the Graylog VM.
* `docker ps -f "name=graylog"` output.
* The `graylog_storage_1` container log.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Graylog container OOM killed

**Symptoms:**

* The Graylog web UI is not accessible, or displays a 504 error.
* The Graylog or OpenSearch containers restart constantly.

**Root cause:**

The Graylog or OpenSearch container exceeds its heap setting and is killed, then restarted.

**How to check:**

1. Log in to the Graylog VM over SSH and run `docker ps`.
2. Read the container status. Containers that restart constantly point at memory.

**How to fix:**

Change the memory settings either through the deploy job or by hand.

Through the deploy job: re-run the Logging service deploy with corrected `graylog_heap_size` and `es_heap_size`
parameters. Prefer this — a manual edit is undone by the next deploy.

By hand:

1. Log in to the Graylog VM over SSH as root.
2. Get the container IDs:

   ```bash
   docker inspect --format '{{.Id}}' graylog_graylog_1
   docker inspect --format '{{.Id}}' graylog_storage_1
   ```

3. **DANGEROUS — stops every container on the VM, so all log collection and search stop until step 6.** Stop Docker:

   ```bash
   service docker stop
   ```

4. In `/var/lib/docker/containers/<container_id>/config.v2.json`, find `GRAYLOG_SERVER_JAVA_OPTS` for Graylog and
   correct its value. For example, from 2 GB:

   ```text
   GRAYLOG_SERVER_JAVA_OPTS = -Xms2048m -Xmx2048m
   ```

   to 4 GB:

   ```text
   GRAYLOG_SERVER_JAVA_OPTS = -Xms4096m -Xmx4096m
   ```

5. Do the same for `ES_JAVA_OPTS` in the OpenSearch container's `config.v2.json`.
6. Start Docker and restart the containers:

   ```bash
   service docker start

   docker restart \
        graylog_web_1 \
        graylog_graylog_1 \
        graylog_storage_1 \
        graylog_mongo_1
   ```

Before raising the OpenSearch heap, read [OpenSearch runs out of heap memory](#opensearch-runs-out-of-heap-memory).
Past roughly 32 GB, more heap makes things worse rather than better, and the sizing rule there also covers how much of
the VM's RAM the two containers may claim between them.

**Data to collect:**

* `docker ps` output showing the restart count.
* The current `GRAYLOG_SERVER_JAVA_OPTS` and `ES_JAVA_OPTS` values.
* Total VM RAM.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Low Graylog performance

**Symptoms:**

* The Graylog web UI is very slow.
* Graylog shows no messages in search within the last 5-15 minutes.
* The UI shows a `Journal utilization is too high` notification.

**Root cause:**

The VM is short of a resource — CPU, RAM, or disk IOPS. Disk speed is the usual one.

**How to check:**

1. Log in to the Graylog VM over SSH as root.
2. Run `top`, or use system monitoring if available.
3. Identify which resource is short against the sizing in the installation guide.

**How to fix:**

1. Add the missing resource to the VM. See [Performance tuning](#performance-tuning) for what to tune once the hardware
   is right. This is the actual fix; the restart below only clears the backlog.
2. **DANGEROUS — log ingestion and search stop until the containers come back.** Restart Graylog:

   ```bash
   docker restart \
       graylog_web_1 \
       graylog_graylog_1 \
       graylog_storage_1 \
       graylog_mongo_1
   ```

3. Go to `/system/inputs` in the UI and press **Stop input**. This prevents Graylog being flooded again while it
   catches up.
4. Go to `/system/nodes` and open **Details** for the node. Wait for the input buffer to drain — that means Graylog has
   processed the backlog.
5. Wait for journal utilization to fall to 0-5%, then start the input again.

**Data to collect:**

* `top` output, or monitoring graphs for CPU, RAM, and disk IOPS.
* Journal utilization from `/system/nodes`.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Graylog not processing messages

**Symptoms:**

* New logs are not available for search.
* Search does not work at all.
* The node page reports `The journal contains X unprocessed messages`, with `X` high and growing.

**Root cause:**

OpenSearch does not take the payload, so the journal grows instead of draining. The underlying reason is one of:

* [HDD full on the Graylog VM](#hdd-full-on-the-graylog-vm)
* [Graylog container OOM killed](#graylog-container-oom-killed)
* [Low Graylog performance](#low-graylog-performance)
* An OpenSearch problem of its own — see
  [OpenSearch cluster status is red or yellow](#opensearch-cluster-status-is-red-or-yellow) and
  [Index read-only warnings](#index-read-only-warnings)

**How to check:**

1. Open `http://<graylog>/system/nodes`.
2. Read `The journal contains X unprocessed messages`.
3. An `X` above 100000 that keeps growing confirms it. See [Performance tuning](#performance-tuning) for what the
   numbers mean.

**How to fix:**

1. Work through the causes above and fix the one that applies. Restarting the containers clears a wedged OpenSearch,
   but it treats the symptom and the journal grows again.

**Data to collect:**

* The unprocessed message count from `/system/nodes`, sampled twice so the trend is visible.
* `df -h` and `docker ps` from the VM.
* OpenSearch `_cluster/health` output.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Negative number of unprocessed messages

**Symptoms:**

* The `Disk Journal` section reports a negative number of unprocessed messages.

**Root cause:**

The journal directory was cleaned, but not completely.

**How to check:**

1. Read the reported count in the `Disk Journal` section of the node page. A negative value is itself the diagnosis —
   there is nothing else to rule out.

**How to fix:**

1. **DANGEROUS — log ingestion stops until step 3.** Stop the Graylog container:

   ```bash
   docker stop graylog_graylog_1
   ```

2. **DANGEROUS — discards every message still buffered in the journal, which has not reached OpenSearch yet and cannot
   be recovered.** Remove the journal directory contents completely. The path is
   `{{ graylog_volume }}/graylog/data/journal/*`, where `graylog_volume` defaults to `/srv/docker/graylog`:

   ```bash
   rm -rf /srv/docker/graylog/graylog/data/journal/*
   ```

3. Start the container:

   ```bash
   docker start graylog_graylog_1
   ```

4. **DANGEROUS — without a journal, any message Graylog holds when OpenSearch stalls or restarts is lost rather than
   buffered.** To switch journal messages off entirely, set `message_journal_enabled=false` in
   `/srv/docker/graylog/graylog/config/graylog.conf`. See [Extra tips and tricks](#extra-tips-and-tricks) for when that
   trade is worth making.

**Data to collect:**

* The `Disk Journal` section of `/system/nodes`.
* A listing of `/srv/docker/graylog/graylog/data/journal/`.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Index oversized

**Symptoms:**

* Disk utilization on the Logging VM exceeds the maximum configured in the index rotation policies.
* One OpenSearch index is far larger than the `Max index size` parameter on its index set.

**Root cause:**

A Graylog indexer bug. It is rare, and only a manual workaround exists.

**How to check:**

1. Check the index sizes on the Logging VM:

   ```bash
   curl -X GET -u <username>:<password> -sk https://localhost/api/system/indexer/indices
   ```

**How to fix:**

1. Take a backup. The next step cannot be undone without one.
2. **DANGEROUS — permanently deletes the index and every log in it.** Delete the oversized index on the Logging VM:

   ```bash
   curl -X DELETE -u <username>:<password> -H "X-Requested-By: graylog" \
     https://localhost/api/system/indexer/indices/<index_name>
   ```

**Data to collect:**

* The `/api/system/indexer/indices` output.
* The `Max index size` setting for the affected index set.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Incorrect timestamps in Graylog

**Symptoms:**

* The `message`, `time`, and `timestamp` fields show different time values or time zones.

**Root cause:**

The nodes' time zone is not UTC.

**How to check:**

1. Check the time zone on each node. It must be UTC.

**How to fix:**

1. Set the time zone to UTC on every node.
2. Alternatively, change the time zone in the Graylog user settings to match the nodes. This does not change the time
   inside the `message` field, which stays UTC, so it hides the mismatch rather than fixing it.

**Data to collect:**

* The time zone on each node.
* One example message showing the differing `message`, `time`, and `timestamp` values.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Information about OpenSearch nodes is unavailable

**Symptoms:**

* **System > Nodes** shows no information about the OpenSearch nodes.
* Clicking a node's name shows an error rather than its details.

**Root cause:**

Graylog's TLS certificate is expired, or its alternative names do not cover the address Graylog uses to reach the node.

**How to check:**

1. Check that the Graylog TLS certificate has not expired.
2. Check that its alternative names cover the address in use. For a Cloud deployment in the `logging` namespace, that
   includes `graylog-service.logging.svc`.

**How to fix:**

1. Reissue the certificate so it is valid and its alternative names cover the address in use. For a self-signed
   certificate, follow the TLS guide's certificate generation section.

**Data to collect:**

* The certificate's expiry date and alternative names.
* The error shown on the node details page.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Widgets do not show data with errors

**Symptoms:**

* A widget reports an error instead of data:

<!-- markdownlint-disable line-length -->
```text
While retrieving data for this widget, the following error(s) occurred:

Unable to perform search query: Elasticsearch exception [
  type=illegal_argument_exception,
  reason=Text fields are not optimized for operations that require per-document field data like aggregations and sorting, so these operations are disabled by default. Please use a keyword field instead. Alternatively, set fielddata=true on [timestamp] in order to load field data by uninverting the inverted index. Note that this can use significant memory.
].
```
<!-- markdownlint-enable line-length -->

* The Graylog log shows a matching `illegal_argument_exception`.

**Root cause:**

A custom OpenSearch index has a field with the wrong type, or an undeclared field.

OpenSearch types new fields dynamically: if a field was never declared and OpenSearch is asked to store data for it, it
picks a type itself. The type it picks may not suit Graylog — Graylog cannot sort on a text field, for example. This is
most common with custom indices, reached by creating a custom index and a stream that routes messages into it.

**How to check:**

1. Read the error and find the field with the wrong type. In the example above it is `timestamp`:

   ```text
   Alternatively, set fielddata=true on [timestamp] in ...
   ```

2. Check the field's type through the OpenSearch API:

   ```text
   GET /_mapping/field/<field>
   GET /<index_name>/_mapping/field/<field>
   GET /_index_template/<index_name>
   ```

**How to fix:**

1. Change the index mapping: declare the field if it was never declared, and set the correct type. A `timestamp` field
   needs the `date` type.

**How to avoid this issue:**

Declare every field for custom OpenSearch indices rather than relying on dynamic typing.

**Data to collect:**

* The full widget error and the matching Graylog log line.
* The output of `GET /<index_name>/_mapping/field/<field>` for the offending field.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Deflector exists as an index and is not an alias

**Symptoms:**

* The Overview page shows the error:

```text
Deflector exists as an index and is not an alias
```

* The Graylog log shows an active write index that does not exist yet:

<!-- markdownlint-disable line-length -->
```text
[2023-10-26T12:49:12,327][WARN]Active write index for index set "v2_cis_inventory_change_log" (653a6047ab6c072bb306a2d5) doesn't exist yet
```
<!-- markdownlint-enable line-length -->

* The OpenSearch log shows the deflector being created as an index by a bulk write:

<!-- markdownlint-disable line-length -->
```text
[2023-10-26T12:49:12,391][INFO ][o.o.c.m.MetadataCreateIndexService] [604eb8d3c4b3] [v2_cis_inventory_change_log_deflector] creating index, cause [auto(bulk api)], templates [v2_cis_inventory_change_log], shards [1]/[1]
```
<!-- markdownlint-enable line-length -->

**Root cause:**

Graylog writes and reads through an alias with a `_deflector` postfix, which it manages itself. The error means
OpenSearch already holds an *index* by that name. That happens in two ways:

1. Somebody manually created an index with the name Graylog wants for its alias.
2. During an update, a stream was already mapped onto an index that did not exist yet, so OpenSearch received a write
   and auto-created the deflector as an index before Graylog could create the index and assign the alias.

**How to check:**

1. Compare the Graylog and OpenSearch logs around the same timestamp, as above. The OpenSearch line naming
   `cause [auto(bulk api)]` confirms the second case.

**How to fix:**

1. **DANGEROUS — permanently deletes the index and anything already written to it.** If the index was created
   manually, remove it. Confirm from the logs above that this is the auto-created `_deflector` index and not a real
   index someone depends on; if you cannot tell which index is offending, stop here rather than guess.
2. **DANGEROUS — stopping inputs drops nothing, but senders buffer and may hit their own limits during a long
   upgrade.** If this happened during an update of the Logging VM, stop all Graylog inputs before the update: open the
   UI, go to **System > Inputs**, and press **Stop input** for each one. Start them again once the upgrade completes.

**How to avoid this issue:**

Do not create indices with a `_deflector` postfix — the alias is reserved by Graylog. Stop all Graylog inputs during
any update that creates streams using custom indices.

**Data to collect:**

* The Graylog and OpenSearch logs around the error.
* The list of indices matching `*_deflector`.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
<!-- markdownlint-enable line-length -->

### Performance tuning

Graylog uses OpenSearch as backend storage and acts as the receiver and processor. Graylog itself needs few resources
and is hard to overload. In most cases OpenSearch is the bottleneck: it cannot take all the logs Graylog sends it,
because it lacks resources. OpenSearch is disk-speed greedy first, RAM greedy second.

When OpenSearch cannot keep up, Graylog's buffers grow, including the disk journal. Graylog then spends disk and CPU on
serving the journal, which slows OpenSearch further, and the system falls into an unstable state.

The symptoms, from small overload to severe:

1. Search operations in Graylog are slow.
2. The journal grows. 0-50k messages is fine, 50k-100k is worse, 500k+ is almost a disaster.
3. Search does not show recent logs, because they sit in the journal rather than in OpenSearch.
4. The UI is slow and returns random 500 and 503 errors.
5. The UI is down.
6. VM CPU is fully utilized and the VM becomes unresponsive, even over SSH.

Principles:

* Check hardware resources against the sizing table in the installation guide first. Disk speed matters most, and
  almost all performance problems can be solved by increasing it.
* Measure disk speed with `sysbench`.
* RAM and CPU come second, but still matter.
* Graylog does not need much RAM — 4-8 GB is enough. Give the rest to OpenSearch, subject to the ceiling in
  [OpenSearch runs out of heap memory](#opensearch-runs-out-of-heap-memory).

### Extra tips and tricks

In `/srv/docker/graylog/graylog/config/graylog.conf`:

* `processbuffer_processors`, `outputbuffer_processors` — set to CPU count / 2.
* `ring_size` — set to 131072, or 262144 with 4+ GB RAM for Graylog. Higher values are not recommended.

Under heavy load, each of these buys throughput at a cost. Take them only when the load justifies the loss:

* Remove the `Logs Routing` pipeline. This saves CPU and loses log routing to streams.
* Disable the disk journal, so Graylog and OpenSearch stop competing for the disk. Buffering across an OpenSearch
  outage is lost.
* Stop collecting system and audit logs on the agent side.

## OpenSearch

### OpenSearch cluster status is red or yellow

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
GET _cluster/health -> {"status":"red"}
GET _cluster/health -> {"status":"yellow"}
```
<!-- markdownlint-enable line-length -->

* Graylog logs report the cluster or indices as unavailable.
* Indexing or search requests fail, or return incomplete results.

**Root cause:**

1. A node left the cluster, so a primary shard is unassigned (red), or only replica shards are unassigned (yellow).
2. A node crossed the high or flood-stage disk watermark, so OpenSearch stopped allocating shards to it — see
   [Index read-only warnings](#index-read-only-warnings).
3. A single-node deployment has an index with `number_of_replicas` above zero, so replica shards can never be assigned
   and the index stays yellow indefinitely.

**How to check:**

1. Read `_cluster/health?level=indices` and `_cat/shards?v` for `UNASSIGNED` shards.
2. Read `_cluster/allocation/explain` for the specific reason a shard will not allocate.
3. Check disk usage on the affected node's data path.

**How to fix:**

1. Free disk space, or adjust the watermark settings, if the cause is disk.
2. Set `number_of_replicas: 0` on indices for a genuine single-node deployment.
3. Re-enable shard allocation with `cluster.routing.allocation.enable` if it was disabled for maintenance.

**Data to collect:**

* `_cluster/health?level=indices`, `_cat/shards?v`, and `_cluster/allocation/explain`.
* Disk usage on the data path.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Cluster health — OpenSearch Documentation](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-health/)
<!-- markdownlint-enable line-length -->

### Index read-only warnings

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
index X is read-only
high disk watermark exceeded
```
<!-- markdownlint-enable line-length -->

* Many `index X is read-only` warnings appear at `https://<graylog_url>/system/indices/failures`.
* Graylog does not store logs in OpenSearch. In and Out message counts are non-zero, but recent logs cannot be found on
  the **Search** page.
* Affected indices carry the `index.blocks.read_only_allow_delete` block.

**Root cause:**

OpenSearch has a disk-allocator feature that marks indices `read-only` when disk utilization gets too high. It is on by
default, and indices become read-only at **95%** disk usage. Two thresholds warn before that:

* Low — **80%**
* High — **90%**

Underneath, the disk filled because old indices, snapshots, or Graylog index sets were never rotated or deleted.

**How to check:**

1. Check disk usage per data node against the watermark percentages above.
2. List the indices carrying the `read_only_allow_delete` block:

   ```bash
   curl -X GET -u <username>:<password> http://localhost:9200/<index_name>
   ```

3. Check Graylog's index rotation and retention configuration for the affected index sets.

**How to fix:**

Free disk space first. The block returns immediately if you only clear it.

1. List the indices and decide which are old enough to lose:

   ```bash
   curl -X GET -u <username>:<password> http://localhost:9200/_cat/indices
   ```

2. **DANGEROUS — permanently deletes those indices and every log in them.** Remove the old indices by name, or by
   several names separated by a comma. Name them explicitly against the list from step 1; a pattern matches more than
   it looks like it does.

   ```bash
   curl -X DELETE -u <username>:<password> http://localhost:9200/graylog_30,graylog_31
   ```

3. **DANGEROUS — deletes index data behind OpenSearch's back, and can corrupt the node if it is still running.** Only
   if OpenSearch is unavailable and its API cannot be used, clean its host directories by hand, then restart the
   OpenSearch container — it will not notice the change otherwise. Prefer step 2 whenever the API answers.

   ```text
   /srv/docker/graylog/opensearch/nodes
   /srv/docker/graylog/opensearch/archives
   /srv/docker/graylog/opensearch/snapshots
   ```

4. **DANGEROUS — removes OpenSearch's own disk-full protection.** Clear the read-only flag once usage is below the high
   watermark. Confirm the disk is actually below 90% first: on a still-full disk this lets OpenSearch write until it
   fills the disk again.

   ```bash
   curl -X PUT -u <username>:<password> -H "Content-Type: application/json" \
     -d '{"index.blocks.read_only_allow_delete": null}' http://localhost:9200/_settings
   ```

5. Re-check the index rotation settings in Graylog. Without this the disk reaches 95% again and the indices lock a
   second time. This is the only step that stops the problem recurring.

**How to avoid this issue:**

Configure index rotation so disk utilization stays low:

* The total rotation size of all index sets should stay under **85%** of total disk size.
* Time-based or message-count-based rotation requires calculating the storage it needs. These strategies can consume
  an unpredictable amount of disk.

**DANGEROUS — disables the only thing standing between an incorrect rotation policy and a completely full disk.** The
disk allocator can be disabled, but do not do this in production. The indices then never lock, so instead of a
recoverable read-only state you get a full disk, which takes the whole stack down:

<!-- markdownlint-disable line-length -->
```bash
curl -X PUT -u <username>:<password> -H "Content-Type: application/json" -d '{"persistent": {"cluster.routing.allocation.disk.threshold_enabled": "false"}}' http://localhost:9200/_cluster/settings
```
<!-- markdownlint-enable line-length -->

**Data to collect:**

* Disk usage per data node.
* `GET /<index_name>/_settings` output for `read_only_allow_delete`.
* The cluster's current watermark settings and Graylog's rotation configuration.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [Cluster settings — OpenSearch Documentation](https://docs.opensearch.org/latest/install-and-configure/configuring-opensearch/cluster-settings/)
<!-- markdownlint-enable line-length -->

### OpenSearch runs out of heap memory

**Symptoms:**

```text
java.lang.OutOfMemoryError: Java heap space
```

* The process is killed or restarted by the OS or the JVM.
* Garbage-collection and memory-pressure metrics show sustained high usage before the crash.
* Performance got *worse*, not better, after more heap was allocated.

**Root cause:**

The heap is sized wrong. Both directions cause the same symptom, and the second surprises people:

1. The heap (`-Xms`/`-Xmx` in `jvm.options`, or `OPENSEARCH_JAVA_OPTS`) is too small for the node's index count, shard
   count, and query load.
2. The heap is above roughly **32 GB**, so the JVM switches from 32-bit to 64-bit Ordinary Object Pointers and loses
   compressed oops. Memory efficiency drops, and it takes **40-50 GB** of allocated heap to regain the effective memory
   of a heap just under 32 GB. Raising the limit past 32 GB therefore makes OOM more frequent, not less.
3. `-Xms` and `-Xmx` differ, so the heap resizes at runtime instead of being locked at startup.
4. The heap is close to or above half of system RAM, starving the OS page cache that OpenSearch relies on for search,
   which raises garbage-collection pressure.

**How to check:**

1. Compare the effective `-Xms`/`-Xmx` values against total system RAM.
2. Read the garbage-collection logs and memory-pressure metrics leading up to the error.
3. Check whether `bootstrap.memory_lock` is enabled and honored.
4. Check whether the limit was recently raised. If OOM started or worsened after an increase past ~32 GB, cause 2 is
   the one.

**How to fix:**

1. Set `-Xms` and `-Xmx` to equal values.
2. Keep the heap under ~32 GB and at roughly half of system RAM, whichever is lower.
3. Size Graylog and OpenSearch together. The VM also runs MongoDB and nginx as containers, and Java processes use more
   than `-Xmx`, so the sum of both heaps must stay below total VM RAM with **20-50% of RAM left free**. Examples, not
   recommendations:

   * 16 GB VM — Graylog 4 GB, OpenSearch 8 GB
   * 32 GB VM — Graylog 8 GB, OpenSearch 12-18 GB
   * 64 GB VM — Graylog 20 GB, OpenSearch 24-31 GB

4. Do not run other memory-heavy processes on the host.

Raising the limit is often reached for instead of diagnosing the real problem. Once OOM stops, look at
[Performance tuning](#performance-tuning) for what was actually short.

**Data to collect:**

* The heap settings from `jvm.options` or `OPENSEARCH_JAVA_OPTS`, and the Graylog heap alongside them.
* Total system RAM.
* The `OutOfMemoryError` excerpt with surrounding garbage-collection activity.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [Installing OpenSearch — OpenSearch Documentation](https://docs.opensearch.org/latest/install-and-configure/install-opensearch/index/)
* [Don't Cross 32 GB! — Elasticsearch: The Definitive Guide](https://www.elastic.co/guide/en/elasticsearch/guide/current/heap-sizing.html#compressed_oops)
<!-- markdownlint-enable line-length -->

### OpenSearch single-node cluster fails to bootstrap

**Symptoms:**

* OpenSearch fails to start, or never reports a healthy status.
* The log shows no cluster manager elected, or a discovery timeout waiting for peer nodes that do not exist in a
  single-node deployment.

**Root cause:**

1. `discovery.type: single-node` is missing, so OpenSearch waits to discover peers that will never appear.
2. `cluster.initial_cluster_manager_nodes` does not list the node's own `node.name`, or lists a mismatched name, so no
   cluster manager is elected.
3. Nodes were bootstrapped with different `cluster.initial_cluster_manager_nodes` values, which OpenSearch rejects to
   avoid a split brain.

**How to check:**

1. Compare `discovery.type` and `cluster.initial_cluster_manager_nodes` in `opensearch.yml` against the node's actual
   `node.name`.
2. Confirm whether this is genuinely meant to be a single-node deployment.
3. Read the startup log for discovery or cluster-formation errors.

**How to fix:**

1. Set `discovery.type: single-node` for a genuine single-node deployment.
2. Otherwise correct `cluster.initial_cluster_manager_nodes` to match the node names used at first bootstrap. Leave it
   empty on nodes joining an already-formed cluster.

**Data to collect:**

* The node's `opensearch.yml` — `discovery.type`, `node.name`, `cluster.initial_cluster_manager_nodes`.
* The startup log showing the discovery or bootstrap failure.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Cluster bootstrapping — OpenSearch Documentation](https://docs.opensearch.org/latest/tuning-your-cluster/discovery-cluster-formation/bootstrapping/)
<!-- markdownlint-enable line-length -->

### Limit of total fields has been exceeded

**Symptoms:**

```text
Limit of total fields [1000] in index [test_index] has been exceeded
```

* The error appears in OpenSearch or Graylog logs, or in responses to API calls.

**Root cause:**

OpenSearch prevents mapping explosions — too many dynamic fields — by refusing new fields in an index once it holds
**1000** of them.

The fields are usually junk produced by the agent that parses logs. FluentBit and FluentD parse new dynamic fields out
of a log's `message` and attach them as metadata. Known bugs make them parse parts of a message as `key=value` pairs.
For example, this log:

<!-- markdownlint-disable line-length -->
```text
[2024-09-30T04:59:40.498] [DEBUG] [request_id=1a04d001-37e6-418b-bc7f-4904d4dfc753] [tenant_id=-] [thread=main-8e36d]
[class=mongo:storage.go:236] [traceId=0000000000000000176d565380a60f8b] [spanId=04546e4d3320dc9b] try to delete objects
from certificates by filter map[$and:[map[meta.status:map[$ne:trusted]] map[$or:[map[meta.deactivatedAt:map[$lte:2024-08-31
04:59:40.498507159 +0000 UTC m=+6199354.549415617]] map[details.validTo:map[$lte:2024-08-31 04:59:40.498507159 +0000 UTC
m=+6199354.549415617]]]]]]
```
<!-- markdownlint-enable line-length -->

yields this field, which is not a field at all:

```text
_lte_2024-08-31_04_59_40_498507159__0000_UTC_m = +6199354.549415617
```

**How to check:**

1. Read the index named in the error.
2. Inspect its mapping for generated `key=value` junk fields.

**How to fix:**

1. Update to the latest version of Logging and check again. Most of these parser bugs are fixed upstream.
2. For an external agent, or logs sent directly to Graylog, check that agent's settings instead.
3. **DANGEROUS — rewrites every document in every index named, which takes hours and heavy CPU on a system that is
   already struggling, and cannot be interrupted cleanly.** Junk fields already stored disappear on their own when
   rotation removes their index, so prefer waiting. Only if you must clean them sooner, and only once the root cause is
   fixed, remove them by prefix.

   ```painless
   List fieldsToRemove = new ArrayList();
   for (entry in ctx._source.keySet()) {
     if (entry.startsWith('ErrorEntry_')) {
       fieldsToRemove.add(entry);
     }
   }
   for (field in fieldsToRemove) {
     ctx._source.remove(field);
   }
   ```

   `ErrorEntry_` is the prefix to change. Run it through the API, where `<index_name>` accepts several indices
   separated by commas, or `*`:

   <!-- markdownlint-disable line-length -->
   ```bash
   curl -X POST -u <username>:<password> -H 'Content-Type: application/json' http://localhost:9200/<index_name>/_update_by_query -d '{
     "query": {
       "match_all": {}
     },
     "script": {
       "lang": "painless",
       "source": "List fieldsToRemove = new ArrayList();\nfor (entry in ctx._source.keySet()) {\n  if (entry.startsWith(\"ErrorEntry_\")) {\n    fieldsToRemove.add(entry);\n  }\n}\nfor (field in fieldsToRemove) {\n  ctx._source.remove(field);\n}"
     }
   }'
   ```
   <!-- markdownlint-enable line-length -->

4. **DANGEROUS — removes the write block, which is usually there because the disk filled.** If the index is locked for
   writing, unlock it first. Check why it was locked before you do — see
   [Index read-only warnings](#index-read-only-warnings).

   <!-- markdownlint-disable line-length -->
   ```bash
   curl -X PUT -u <username>:<password> -H 'Content-Type: application/json' -d '{"index.blocks.write": "false"}' http://localhost:9200/<index_name>/_settings
   ```
   <!-- markdownlint-enable line-length -->

**Data to collect:**

* The full error with the index name.
* The index mapping, showing the junk fields.
* The agent version and its parser configuration.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [Mapping limit settings — OpenSearch Documentation](https://opensearch.org/docs/latest/field-types/#mapping-limit-settings)
* [Update by query — OpenSearch Documentation](https://opensearch.org/docs/latest/api-reference/document-apis/update-by-query/#path-parameters)
<!-- markdownlint-enable line-length -->

### Errors no such index .opendistro-ism-config

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
[2024-10-11T11:47:21,697][ERROR][o.o.i.i.ManagedIndexCoordinator] [881c8d26fd21] get managed-index failed: [.opendistro-ism-config] IndexNotFoundException[no such index [.opendistro-ism-config]]
```
<!-- markdownlint-enable line-length -->

**Root cause:**

This error has no effect. The `index-management` plugin logs it whenever an index is deleted: the plugin checks for its
own metadata about that index, and the `.opendistro-ism-config` index does not exist because no ISM policy was ever
created. The plugin authors agree the `ERROR` level is inappropriate here and lowered it to `DEBUG` in version 2.10.0.0.

**How to check:**

1. Confirm the message matches the text above and that no ISM policy exists. There is nothing broken to find.

**How to fix:**

Ignore it. Nothing is broken, and this is the recommended action.

If the noise is genuinely unacceptable, add at least one ISM rule so OpenSearch creates the system index. That is the
safe option.

**DANGEROUS — turns off index state management, so any ISM policy stops running and index lifecycle automation silently
stops.** Disabling the plugin also silences the message, but it trades a harmless log line for a real loss of function:

```yaml
plugins.index_state_management.enabled: False
```

Upgrading OpenSearch to 2.10 or later also silences it, once such an upgrade is available here.

**Data to collect:**

* The full error line, to confirm it is this message and not a different `IndexNotFoundException`.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [index-management issue 697 — OpenSearch](https://github.com/opensearch-project/index-management/issues/697)
* [ISM settings — OpenSearch Documentation](https://opensearch.org/docs/latest/im-plugin/ism/settings/)
<!-- markdownlint-enable line-length -->

## MongoDB

### MongoDB fails to start

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
featureCompatibilityVersion
```
<!-- markdownlint-enable line-length -->

* `rs.status()` reports the set as not initialized, or Graylog cannot find a primary.
* Or `mongod` exits immediately after a version upgrade and enters a restart loop.

**Root cause:**

1. `rs.initiate()` was never run on the intended primary, so the replica set has no configuration and no member can
   become primary.
2. `mongod` was not started with `--replSet <name>` (or `replication.replSetName`) matching the name used in
   `rs.initiate()`.
3. After a major-version upgrade, the on-disk `featureCompatibilityVersion` was left at the previous version, and the
   new binary refuses to start until it is raised.

**How to check:**

1. Read `rs.status()` and `rs.conf()` on each member.
2. Check the `--replSet`/`replication.replSetName` value each `mongod` was started with.
3. For upgrade failures, compare the FCV recorded in the admin database against the new binary's required minimum.

**How to fix:**

1. Run `rs.initiate()` on the intended primary if the set was never initialized. Use hostnames, not bare IP addresses.
2. Align `replSetName` across all members.
3. For an upgrade failure, start the previous binary version, run
   `db.adminCommand({setFeatureCompatibilityVersion: "<target_version>"})`, then retry the upgrade.

If the container instead crash-loops with an `invariant()` or `SIGABRT` error from WiredTiger, this is not the case —
see [MongoDB container crash-loops on a WiredTiger invariant](#mongodb-container-crash-loops-on-a-wiredtiger-invariant).

**Data to collect:**

* `rs.status()` and `rs.conf()` output.
* Each member's `mongod` startup flags or config file.
* The exact startup error for upgrade failures, including the reported FCV.

**Sources:**

<!-- markdownlint-disable line-length -->
* [rs.initiate() (mongosh method) — MongoDB Docs](https://www.mongodb.com/docs/manual/reference/method/rs.initiate/)
* [Upgrade a Standalone to 8.0 — MongoDB Docs](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-standalone/)
<!-- markdownlint-enable line-length -->

### MongoDB container crash-loops on a WiredTiger invariant

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
Got signal: 6 (Aborted)
invariant()
```
<!-- markdownlint-enable line-length -->

* The `graylog_mongo_1` container restarts repeatedly.
* The log shows an `invariant()` failure at startup, with a WiredTiger error before the abort.

**Root cause:**

1. An unclean shutdown — host crash, OOM kill, or a full disk during a write — corrupted the on-disk WiredTiger data
   files, so the storage engine hits an internal invariant it cannot recover from.
2. The data volume ran out of disk space mid-write, truncating a data or journal file.
3. The container was killed mid-checkpoint, leaving WiredTiger metadata in a state its own consistency checks reject.

**How to check:**

1. Read the container's exit code and restart count with `docker ps` and `docker inspect`.
2. Check disk usage on the volume backing MongoDB's data directory.
3. Check whether the same `invariant()` text recurs identically on every restart attempt. It does when the data is
   corrupt.

**How to fix:**

1. Free disk space on the data volume if it is full.
2. Restore a recent backup. This is the preferred fix, and the only one that does not risk losing data.
3. **DANGEROUS — `--repair` discards whatever it cannot recover, permanently, and there is no undo once it starts.**
   Only if no backup exists, stop the container and run `mongod --repair` against the data directory. Copy the data
   directory first if the disk has room: that copy is the only way back if the repair makes things worse.

This is a storage-engine crash. For a startup failure driven by replica-set initialization or
`featureCompatibilityVersion`, see [MongoDB fails to start](#mongodb-fails-to-start).

**Data to collect:**

* The full container log from the `invariant()`/`SIGABRT` event back to the last clean checkpoint.
* Disk usage on the data volume.
* The container's restart and exit-code history.

**Sources:**

<!-- markdownlint-disable line-length -->
* [WiredTiger Storage Engine — MongoDB Docs](https://www.mongodb.com/docs/manual/core/wiredtiger/)
* [mongod — MongoDB Docs](https://www.mongodb.com/docs/manual/reference/program/mongod/)
<!-- markdownlint-enable line-length -->

## FluentD

The FluentD agent on the Graylog VM is deployed by `roles/fluentd`, runs as `graylog_fluentd_1`, and collects the VM's
own container logs. Its configuration lives in `roles/fluentd/files/conf.d/` and
`roles/fluentd/templates/output-graylog.conf.j2`. Apply configuration changes through the role and redeploy — an edit
made inside the container is lost on the next run.

### FluentD worker is killed with SIGKILL

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
2024-05-14 10:14:23 +0000 [error]: Worker 1 exited unexpectedly with signal SIGKILL
2024-05-14 10:14:25 +0000 [info]: #1 init workers logger path=nil rotate_age=nil rotate_size=nil
```
<!-- markdownlint-enable line-length -->

* FluentD uses a lot of disk read operations and throughput after the restart.
* The VM's `dmesg` log shows an OOM kill for a `ruby` process.

**Root cause:**

FluentD runs more than one process inside the container — a supervisor plus two workers, `#0` and `#1`. Worker `#1`
collects, processes, and sends logs, and holds the buffer.

When the buffer does not fit in available memory, the OOM killer takes worker `#1` and the supervisor restarts it. The
restarted worker re-reads its buffer from disk, which is where the disk read spike comes from — the high disk load is a
symptom of this crash loop, not a separate problem.

**How to check:**

1. Look for the `SIGKILL` line and the repeated worker restarts in the FluentD log.
2. Check `dmesg` on the VM for an OOM kill of a `ruby` process.
3. Check free RAM on the VM. The role sets no container memory limit, so the ceiling is the VM's own memory, shared
   with Graylog, OpenSearch, and MongoDB.

**How to fix:**

1. Reduce the buffer so it fits in available memory. In `roles/fluentd/templates/output-graylog.conf.j2` the buffer is
   bounded by `chunk_limit_size` and `queue_limit_length`, whose product is the ceiling. Lower one of them, or set an
   explicit `total_limit_size`:

   ```xml
   <store ignore_error>
     @type gelf
     # other parameters
     <buffer>
       total_limit_size 512Mb
     </buffer>
   </store>
   ```

2. Or give the VM more RAM, having first checked that the Graylog and OpenSearch heaps are not already claiming it —
   see [OpenSearch runs out of heap memory](#opensearch-runs-out-of-heap-memory).
3. Redeploy the role to apply the change.

**Data to collect:**

* The FluentD log around the `SIGKILL`.
* `dmesg` output showing the OOM kill.
* Free RAM on the VM, and the buffer settings in effect.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [Config: Buffer Section — Fluentd](https://docs.fluentd.org/configuration/buffer-section)
<!-- markdownlint-enable line-length -->

### FluentD buffer fills and stops accepting logs

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
buffer space has too many data
BufferOverflowError
```
<!-- markdownlint-enable line-length -->

* Log delivery falls behind, or events are dropped during traffic spikes.
* FluentD retries the same chunk indefinitely without draining.

**Root cause:**

1. Graylog accepts data more slowly than FluentD produces it — during a Graylog restart, or an OpenSearch backlog — so
   the buffer fills faster than it drains.
2. The buffer is too small for the sustained rate. In `roles/fluentd/templates/output-graylog.conf.j2` the ceiling is
   `chunk_limit_size` times `queue_limit_length`.
3. The output sets `retry_forever true`, so FluentD never discards a chunk it cannot deliver. Across a long Graylog
   outage the buffer fills and blocks rather than dropping data. This is deliberate — the trade is delivery over
   liveness — but it makes an outage look like a FluentD fault.

**How to check:**

1. Read the output plugin's retry and error log for the affected window.
2. Check Graylog and OpenSearch health for the same window — see
   [Graylog not processing messages](#graylog-not-processing-messages). A full FluentD buffer is usually a Graylog
   problem seen from the other end.
3. Compare the buffer ceiling against actual throughput.

**How to fix:**

1. Fix the slowness on the Graylog or OpenSearch side so the buffer drains. This is the real fix in most cases.
2. Raise `chunk_limit_size` or `queue_limit_length` in the role template to absorb realistic bursts, then redeploy.
3. Decide deliberately whether `retry_forever true` is right for this deployment. Bounding it with `retry_max_times`
   drops data after an outage of a known length, instead of blocking.

**Data to collect:**

* The FluentD buffer configuration in effect.
* The log showing the overflow or repeated retries.
* Graylog and OpenSearch health for the same window.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Config: Buffer Section — Fluentd](https://docs.fluentd.org/configuration/buffer-section)
<!-- markdownlint-enable line-length -->

## FluentBit

The FluentBit agent on the Graylog VM is deployed by `roles/fluentbit`, runs as `graylog_fluentbit_1`, and collects the
VM's own container logs. Its configuration lives in `roles/fluentbit/files/conf/` and
`roles/fluentbit/templates/output-graylog.conf.j2`. Apply configuration changes through the role and redeploy.

FluentD and FluentBit are alternatives — a VM runs one of them, not both.

### FluentBit cannot deliver logs to Graylog

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
[2024/04/25 20:54:28] [error] [upstream] connection #-1 to tcp://unavailable:0 timed out after 10 seconds (connection timeout)
[2024/04/25 20:54:29] [ warn] [net] getaddrinfo(host='<graylog_url>', err=12): Timeout while contacting DNS servers
[2024/04/25 20:54:29] [error] [output:gelf:gelf.1] no upstream connections available
```
<!-- markdownlint-enable line-length -->

* Or `TCP connection failed: <graylog_host>:12201 (Connection refused)`.
* A TLS-enabled output reports a handshake failure instead.
* The Graylog input shows no incoming messages from this VM.

**Root cause:**

1. FluentBit is starved of CPU. This is the usual cause of the DNS and connection timeouts above — the resolver times
   out because the process cannot run, not because the network is broken.
2. The Graylog input is not running, is bound to a different port than the output targets, or had not started when
   FluentBit connected.
3. A firewall blocks the input's port, or the input's port or protocol changed without the output being updated.
4. The output has TLS on, but the CA, the certificate's validity, or its alternative names do not match the host the
   output connects to, so the handshake fails before any data is sent.

**How to check:**

1. Check FluentBit's CPU consumption first. The DNS timeout in the log is a symptom of CPU starvation more often than
   of DNS.
2. Check that the Graylog input is running and listening on the expected port, from **System > Inputs**.
3. Test reachability from the VM, for example `nc -zv <graylog_host> <port>`.
4. For TLS, compare `fluentbit_tls_ca`, `fluentbit_tls_verify`, and the certificate's alternative names against the
   host configured in the output.

**How to fix:**

1. Give FluentBit more CPU.
2. Add network and health-check settings to the output so a slow resolver does not fail the connection outright:

   ```text
   [SERVICE]
       Flush         5
       HC_Errors_Count 5
       HC_Retry_Failure_Count 5
       HC_Period 5

   [OUTPUT]
       Name     gelf
       # other parameters
       net.connect_timeout 20s
       net.max_worker_connections 35
       net.dns.mode TCP
       net.dns.resolver LEGACY
   ```

3. Confirm the Graylog input is enabled on the port the output targets, and open the port between the hosts.
4. Align the output's TLS settings with the input's actual certificate.
5. Apply the change through `roles/fluentbit` and redeploy, then restart the container.

**Data to collect:**

* The FluentBit output configuration and its log around the failure.
* The Graylog input's port, protocol, and TLS setting.
* A reachability test from the VM to the Graylog input port.
* FluentBit's CPU usage during the failure.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [Graylog Extended Log Format (GELF) output — FluentBit manual](https://docs.fluentbit.io/manual/data-pipeline/outputs/gelf)
* [Secure Inputs with TLS — Graylog documentation](https://go2docs.graylog.org/current/getting_in_log_data/secure_inputs_with_tls.htm)
<!-- markdownlint-enable line-length -->

### FluentBit stops sending logs and stays stuck

**Symptoms:**

* FluentBit is stuck and sends no logs at all.
* The output logs no connection error — unlike
  [FluentBit cannot deliver logs to Graylog](#fluentbit-cannot-deliver-logs-to-graylog), nothing is being attempted.

**Root cause:**

The `rewrite_tag` filter re-emits records under a new tag through an emitter. When records stop matching the output's
`Match` rule after a rewrite, or the emitter's buffer stalls, the pipeline stops moving and no error is raised. The
role's filters use `rewrite_tag` with `Emitter_*` settings in `filter-empty-log.conf` and `filter-audit.conf`, and the
output matches `parsed.**`.

**How to check:**

1. Confirm the input is still reading — its metrics increase — while the output's do not.
2. Compare the tags the `rewrite_tag` filters emit against the output's `Match` rule. Records emitted under a tag the
   output does not match are silently dropped.
3. Check the emitter's buffer settings, for example `Emitter_Mem_Buf_Limit 10M`.

**How to fix:**

1. Upgrade to the latest version of Logging first. This is fixed upstream, and the steps below are a temporary
   workaround.
2. Widen the output's match so both raw and parsed records are delivered. Change:

   ```text
   Match   parsed.**
   ```

   to:

   ```text
   Match_Regex (raw|parsed).**
   ```

3. If a `rewrite_tag` filter is not needed, remove it rather than working around it.
4. Apply the change through `roles/fluentbit`, redeploy, and restart the container so the new configuration is read.

**Data to collect:**

* The FluentBit configuration, showing the filters' emitted tags and the output's `Match` rule.
* Input and output metrics, showing where the pipeline stops.
* The FluentBit log for the stuck period.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Troubleshooting — qubership-logging-operator](https://github.com/Netcracker/qubership-logging-operator/blob/main/docs/troubleshooting.md)
* [Rewrite Tag — FluentBit manual](https://docs.fluentbit.io/manual/data-pipeline/filters/rewrite-tag)
<!-- markdownlint-enable line-length -->

## nginx

### Graylog web UI returns 502 behind nginx

**Symptoms:**

<!-- markdownlint-disable line-length -->
```text
502 Bad Gateway
connect() failed (111: Connection refused) while connecting to upstream
upstream prematurely closed connection
```
<!-- markdownlint-enable line-length -->

* Graylog may still answer directly on its own bind port.

**Root cause:**

1. Graylog is down, still starting, or listening on a different address or port than the one `graylog_web_1` proxies
   to.
2. nginx is missing the `X-Graylog-Server-URL` header, or the equivalent `http_external_uri`/`http_publish_uri`
   setting, so Graylog's redirects do not match what the proxy or browser expects.
3. nginx's upstream timeout is shorter than Graylog's response time under load, turning a slow response into a gateway
   error.

**How to check:**

1. Check whether Graylog answers directly on its configured `http_bind_address` port from the VM.
2. Read the upstream failure line in the nginx error log. `Connection refused` and `prematurely closed` mean different
   things — down versus slow.
3. Check the `proxy_pass` target and header configuration in the nginx server block.

**How to fix:**

1. Confirm Graylog is running and bound to the address nginx expects. If it is not, see
   [Unable to connect to Graylog via browser](#unable-to-connect-to-graylog-via-browser).
2. Add or correct the `X-Graylog-Server-URL` header and the related `proxy_set_header` directives.
3. Raise `proxy_connect_timeout` or `proxy_read_timeout` only if the backend is slow rather than down. If it is slow,
   the real fix is in [Low Graylog performance](#low-graylog-performance).

**Data to collect:**

* The nginx error log around the failure timestamp.
* `curl -v` output against Graylog directly and through nginx.
* The nginx server block proxying to Graylog.

**Sources:**

<!-- markdownlint-disable line-length -->
* [The Web Interface — Graylog documentation](https://go2docs.graylog.org/current/setting_up_graylog/web_interface.htm)
* [Module ngx_http_proxy_module — nginx](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
<!-- markdownlint-enable line-length -->

### TLS certificate is not trusted by clients

**Symptoms:**

```text
unable to get local issuer certificate
```

* Browsers or `curl` report a chain-validation error against the nginx-fronted URL, even though the certificate has not
  expired.

**Root cause:**

1. `ssl_certificate` points to the leaf certificate only, without the issuing CA's intermediate certificates
   concatenated after it, so clients that do not already trust the intermediate cannot build a chain.
2. The leaf and intermediate bundle are concatenated in the wrong order. The leaf must come first; some clients
   tolerate the wrong order and others reject it.
3. The certificate's Subject Alternative Name does not include the hostname clients use.

**How to check:**

1. Read the chain nginx serves:

   ```bash
   openssl s_client -connect <host>:443 -showcerts
   ```

2. Check the order and completeness of the file referenced by `ssl_certificate`.
3. Compare the certificate's SAN entries against the hostname in use.

**How to fix:**

1. Concatenate the leaf certificate followed by the CA's intermediate certificates into the file referenced by
   `ssl_certificate`, in that order, then reload nginx.
2. Reissue the certificate if its SAN does not cover the hostname in use.

**Data to collect:**

* `openssl s_client -connect <host>:443 -showcerts` output.
* The nginx `ssl_certificate` and `ssl_certificate_key` configuration.
* The hostname clients use to connect.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Module ngx_http_ssl_module — nginx](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
<!-- markdownlint-enable line-length -->

## Keepalived

### Keepalived virtual IP does not fail over

**Symptoms:**

* The backup node does not take over the virtual IP after the master fails, or after its health check fails.
* `ip addr` on the backup never shows the VIP.
* The Keepalived log stays in `BACKUP` state, or a node stays stuck in `FAULT` state.

**Root cause:**

1. A `vrrp_script` health check times out instead of returning a failure exit code, and the instance does not treat a
   timeout as a failed check, so failover never triggers.
2. Two VRRP instances on the same network segment share a `virtual_router_id`, causing packet conflicts and
   unpredictable state.
3. The interface Keepalived binds to had no IP address configured before Keepalived started, leaving the instance stuck
   in `FAULT`.

**How to check:**

1. Read the Keepalived log on both nodes for VRRP state transitions.
2. Compare the `vrrp_script` timeout against how long the health check actually takes.
3. Compare `virtual_router_id` values across every instance on the segment.
4. Check that the bound interface has a real IP address.

**How to fix:**

1. Give the health-check script a timeout comfortably shorter than the `vrrp_script` interval, and make sure it always
   returns a definite exit code.
2. Make `virtual_router_id` unique per VRRP instance on the segment.
3. Confirm the bound interface has an IP address before Keepalived starts.

**Data to collect:**

* Keepalived logs from both nodes around the failed-over event.
* The `vrrp_instance` and `vrrp_script` configuration.
* `ip addr` output from both nodes.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Case Study: Failover using VRRP — Keepalived documentation](https://keepalived.readthedocs.io/en/latest/case_study_failover.html)
<!-- markdownlint-enable line-length -->
