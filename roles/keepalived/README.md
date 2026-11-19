# keepalived

Holds one virtual IP across two or more hosts with VRRP. A stack passes its own health check, and a node gives up the
VIP while that check fails.

```yaml
- ansible.builtin.include_role:
    name: qubership.observability.keepalived
  vars:
    keepalived_check_script: "{{ lookup('ansible.builtin.file', 'keepalived_check.sh') }}"
  when: observability_vip | default('') | length > 0
```

| Variable | Default | Description |
| --- | --- | --- |
| `observability_vip` | required | Virtual IPv4 address. |
| `observability_vip_interface` | required | Interface that holds the VIP. |
| `keepalived_vip_prefix` | required | Prefix length of the VIP, such as `24`. |
| `keepalived_virtual_router_id` | required | VRRP router ID, 1 to 255. It must be unique per VIP in the network segment. |
| `keepalived_auth_password` | required | VRRP password, 1 to 8 characters. Keep it in a vault. |
| `keepalived_priority` | `100` | Election priority. Give each node a different value. |
| `keepalived_unicast_peers` | `[]` | Addresses of the other nodes, for networks that drop multicast. Empty means multicast. |
| `keepalived_check_script` | `""` | Content of a POSIX `sh` script that exits `0` while the node can serve. |
| `keepalived_check_interval`, `keepalived_check_timeout` | `5`, `10` | Seconds between checks, and seconds one check may take. |
| `keepalived_check_fall`, `keepalived_check_rise` | `2`, `2` | Failures in a row before the node gives up the VIP, and successes before it takes part again. |

Every node starts as `BACKUP` with `nopreempt`, so a recovered node does not take the VIP back from a healthy one.
The role restarts keepalived only when its config or check script changes.

## Upgrading from the earlier Graylog installer

The installer used to configure keepalived inside `prepare_environment`, with a fixed `/24` prefix and the last octet
of the VIP as the router ID. The role now requires both settings. To keep the same VRRP setup, set
`keepalived_vip_prefix: 24` and `keepalived_virtual_router_id` to the last octet of the VIP. The old names
`keepalived_virtual_ip_address` and `keepalived_network_interface` still work.

The earlier installer also skipped keepalived silently when the package was missing. The role now installs it.
