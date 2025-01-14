function add_hostname(tag, timestamp, record)
    file = io.open("/etc/docker-hostname")
    record["hostname"] = file:read()
    file:close()
    return 1, timestamp, record
end