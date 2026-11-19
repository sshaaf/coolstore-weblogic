package com.redhat.coolstore.demo;

import com.fasterxml.jackson.databind.ObjectMapper;
import javax.servlet.http.HttpServletRequest;

/**
 * Proven taint: request input reaches ObjectMapper.readValue.
 * rgctl vuln analyze reports exploitable without extra flags.
 */
public class TaintedOrderParser {
    public Object handle(HttpServletRequest request) throws Exception {
        String raw = request.getParameter("payload");
        ObjectMapper mapper = new ObjectMapper();
        return mapper.readValue(raw, Object.class);
    }
}
