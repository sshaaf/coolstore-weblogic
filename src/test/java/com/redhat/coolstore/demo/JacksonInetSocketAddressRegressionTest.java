package com.redhat.coolstore.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.lang.reflect.Proxy;
import java.net.InetSocketAddress;
import javax.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;

/**
 * Regression coverage for GHSA-hgj6-7826-r7m5 / CVE-2026-54514.
 *
 * <p>Before 2.18.8, jackson-databind built {@link InetSocketAddress} instances with
 * {@code new InetSocketAddress(host, port)}, which performs an eager DNS lookup while
 * binding JSON. The fix uses {@code InetSocketAddress.createUnresolved(host, port)}, so
 * a successfully bound address stays unresolved until an explicit connect.</p>
 */
class JacksonInetSocketAddressRegressionTest {

    /** Holder mirroring an application type that exposes an InetSocketAddress field. */
    public static class AddressHolder {
        public InetSocketAddress address;
    }

    @Test
    void objectMapperDefersDnsResolutionWhenBindingInetSocketAddress() throws Exception {
        AddressHolder holder = new ObjectMapper()
                .readValue("{\"address\":\"localhost:8080\"}", AddressHolder.class);

        assertNotNull(holder.address);
        assertTrue(holder.address.isUnresolved(),
                "jackson-databind must bind via createUnresolved and not resolve DNS eagerly");
        assertEquals("localhost", holder.address.getHostString());
        assertEquals(8080, holder.address.getPort());
    }

    @Test
    void taintedOrderParserBindsAddressPayloadWithoutEagerDns() throws Exception {
        String payload = "{\"address\":\"localhost:8080\"}";
        HttpServletRequest request = requestReturning("payload", payload);

        Object bound = new TaintedOrderParser().handle(request);

        AddressHolder holder = new ObjectMapper().convertValue(bound, AddressHolder.class);
        assertNotNull(holder.address);
        assertTrue(holder.address.isUnresolved(),
                "TaintedOrderParser path must not resolve DNS during deserialization");
    }

    @Test
    void inconclusiveJsonParserBindsAddressPayloadWithoutEagerDns() throws Exception {
        String payload = "{\"address\":\"localhost:8080\"}";

        Object bound = new InconclusiveJsonParser().parse(payload);

        AddressHolder holder = new ObjectMapper().convertValue(bound, AddressHolder.class);
        assertNotNull(holder.address);
        assertTrue(holder.address.isUnresolved(),
                "InconclusiveJsonParser path must not resolve DNS during deserialization");
    }

    private static HttpServletRequest requestReturning(String parameterName, String value) {
        return (HttpServletRequest) Proxy.newProxyInstance(
                JacksonInetSocketAddressRegressionTest.class.getClassLoader(),
                new Class<?>[] {HttpServletRequest.class},
                (proxy, method, args) -> {
                    if ("getParameter".equals(method.getName())
                            && args != null
                            && args.length == 1
                            && parameterName.equals(args[0])) {
                        return value;
                    }
                    Class<?> returnType = method.getReturnType();
                    if (returnType == boolean.class) {
                        return false;
                    }
                    if (returnType == int.class) {
                        return 0;
                    }
                    if (returnType == long.class) {
                        return 0L;
                    }
                    return null;
                });
    }
}
