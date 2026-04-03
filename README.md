## install-hysteria.sh

# Шаг 1. Полностью снести текущую установку

systemctl stop hysteria-server.service 2>/dev/null; systemctl disable hysteria-server.service 2>/dev/null; rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service; rm -rf /etc/hysteria; rm -f /usr/local/bin/hysteria; systemctl daemon-reload; systemctl reset-failed


# Шаг 2. Убедиться, что всё реально снесено

systemctl status hysteria-server.service --no-pager -l
ss -ulnp | grep 8443
which hysteria


# Шаг 3. Запустить твой скрипт заново
curl -fsSL https://raw.githubusercontent.com/Denis33674/install-hysteria.sh/main/install-hysteria2.sh | bash


# Шаг 4. После установки сразу проверить результат
systemctl status hysteria-server.service --no-pager -l
ss -ulnp | grep 8443
journalctl -u hysteria-server.service -n 30 --no-pager -l


# Повторный вывод qr кода
qrencode -t ansiutf8 "$(awk -F'"' '/^server:/{srv=$2} /^auth:/{auth=$2} /^    pinSHA256:/{pin=$2} END{print "hysteria2://" auth "@" srv "/?insecure=1&pinSHA256=" pin}' /etc/hysteria/client-example.yaml)"
