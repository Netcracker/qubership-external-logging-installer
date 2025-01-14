function mark(tag, timestamp, record)
    if (record["level"] == "error") then
        record["level"] = 3
        return 1, timestamp, record
    end
end