package com.redhat.coolstore.service;

import java.util.logging.Logger;
import javax.ejb.Stateless;
import javax.annotation.Resource;
import javax.inject.Inject;
import javax.jms.ConnectionFactory;
import javax.jms.JMSContext;
import javax.jms.Topic;

import com.redhat.coolstore.model.ShoppingCart;
import com.redhat.coolstore.utils.Transformers;

@Stateless
public class ShoppingCartOrderProcessor  {

    @Inject
    Logger log;

    @Resource(lookup = "weblogic.jms.ConnectionFactory")
    private ConnectionFactory connectionFactory;

    @Resource(lookup = "jms/topic/orders")
    private Topic ordersTopic;

    public void process(ShoppingCart cart) {
        log.info("Sending order from processor: ");
        try (JMSContext context = connectionFactory.createContext()) {
            context.createProducer().send(ordersTopic, Transformers.shoppingCartToJson(cart));
        }
    }

}
