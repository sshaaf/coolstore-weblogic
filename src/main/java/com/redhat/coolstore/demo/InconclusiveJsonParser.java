package com.redhat.coolstore.demo;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Inconclusive sink: readValue receives a parameter rgctl cannot trace to an
 * external source. Default verdict is under_investigation; --strict-reachability
 * elevates it to exploitable.
 */
public class InconclusiveJsonParser {
    public Object parse(String body) throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        return mapper.readValue(body, Object.class);
    }
}
