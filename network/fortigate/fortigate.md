# Fortigate

## BGP

## Clear neighbor (soft)
```
execute router clear bgp ip <IP DEL VECINO> soft
```

## Tuneles entre sedes HA

## Es un ejemplo de un link-monitor de Belen, la mayoria son muy parecidos
## quizas cambian entre Quincy y Quincy_Tunnel_1
```

confing system link-monitor
        edit "Quincy"
                set srcintf "Quincy_Tunnel_1"
                set server "172.16.7.101"
                set source-ip "172.16.7.1"
        next
end

```

