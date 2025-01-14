function mark(tag, timestamp, record)
    if (record["log"] == nil or record["log"] == "") and (record["message"] == nil or record["message"] == "") then
        record["empty"] = "true"
        return 1, timestamp, record
    else
        record["empty"] = "false"
        return 1, timestamp, record
    end
end