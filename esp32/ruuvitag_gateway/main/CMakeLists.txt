idf_component_register(SRCS "main.c"
                    PRIV_REQUIRES nvs_flash esp_wifi esp_event esp_netif mqtt bt
                    INCLUDE_DIRS ".")
