# install-hysteria

Данный скрипт ставит на VPS сервер Hysteria2 (VPN), установка возможно вместе с другими VPN таких как VLESS или AMNEZIA
Протестировано и работает на клиенте Shadowrocket на iPhone.


### Шаг 1. Запустить скрипт для установки Hysteria 2

```bash
curl -fsSL https://raw.githubusercontent.com/Denis33674/install-hysteria.sh/main/install-hysteria2.sh | bash
```


### Шаг 2. После установки сразу проверить результат (При желании)

```bash
systemctl status hysteria-server.service --no-pager -l; ss -ulnp | grep 8443; journalctl -u hysteria-server.service -n 30 --no-pager -l
```

### Вывод QR-кода

```bash
qrencode -t ansiutf8 "$(awk -F'"' '/^server:/{srv=$2} /^auth:/{auth=$2} /^    pinSHA256:/{pin=$2} END{print "hysteria2://" auth "@" srv "/?insecure=1&pinSHA256=" pin}' /etc/hysteria/client-example.yaml)"
```

### Очистка сервера от предыдущих установок Hysteria 2

```bash
systemctl stop hysteria-server.service 2>/dev/null; systemctl disable hysteria-server.service 2>/dev/null; rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service; rm -rf /etc/hysteria; rm -f /usr/local/bin/hysteria; systemctl daemon-reload; systemctl reset-failed
```
### Шаг 2. Убедиться, что Hysteria 2 удалена

```bash
systemctl status hysteria-server.service --no-pager -l; ss -ulnp | grep 8443; which hysteria
```

