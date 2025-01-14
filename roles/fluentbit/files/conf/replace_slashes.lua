function replace(tag, timestamp, record)
    if (record["tag"] ~= nil) then
      record["tag"]=record["tag"]:gsub("%/", "."):sub(2)
    end
    return 1, timestamp, record
end