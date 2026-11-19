# Local "on-prem" lab: an Ubuntu VM that Ansible provisions exactly like a
# data-center server.   vagrant up && make deploy-vagrant
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  config.vm.define "app01" do |node|
    node.vm.hostname = "app01"
    node.vm.network "private_network", ip: "192.168.56.11"
    node.vm.provider "virtualbox" do |vb|
      vb.name   = "payflow-app01"
      vb.memory = 1024
      vb.cpus   = 1
    end
  end
end
