package com.redhat.coolstore.utils;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import javax.ejb.Singleton;
import javax.ejb.Startup;
import javax.inject.Inject;
import java.util.logging.Logger;

@Singleton
@Startup
public class StartupListener {

    @Inject
    Logger log;

    @PostConstruct
    public void onStartup() {
        log.info("CoolStore Application Started");
    }

    @PreDestroy
    public void onShutdown() {
        log.info("CoolStore Application Stopping");
    }

}
