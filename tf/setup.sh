#https://allanphilipbarku.medium.com/setup-automatic-local-domains-with-dnsmasq-on-macos-ventura-b4cd460d8cb3

brew install dnsmasq
mkdir -pv $(brew --prefix)/etc/
IP=$(kubectl get svc nginx-ingress-controller -o json | jq -r ".status.loadBalancer.ingress[0].ip")
FILE="$(brew --prefix)/etc/dnsmasq.conf"
ADDRESS="address=/minikube/$IP"
if ! grep -q $ADDRESS "$FILE"; then
  echo $ADDRESS >> $FILE
fi

brew services start dnsmasq
bash -c 'echo "nameserver 127.0.0.1" > /etc/resolver/minikube'
minikube tunnel
