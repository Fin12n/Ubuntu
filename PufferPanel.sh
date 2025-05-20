echo "=== Starting Install PufferPanel (by Finnn) ==="
sudo apt update && sudo apt upgrade
echo "=== Installing UFW ==="
sudo apt install ufw
sudo ufw enable
sudo ufw allow 8080
sudo ufw allow 5657
echo "=== Installing Puffer Panel ==="
curl -s https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true | sudo bash
sudo apt update
sudo apt-get install pufferpanel
echo "=== Finish !!! ==="
echo "Add User: " | echo "sudo pufferpanel user add"
echo "Start Panel: " | echo "sudo systemctl enable --now pufferpanel"
