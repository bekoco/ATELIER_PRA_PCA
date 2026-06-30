ps://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
k3d cluster create pra --servers 1 --agents 2
kubectl get nodes

echo -e "\nInstallation du logiciel Packer..."
PACKER_VERSION=1.11.2
curl -fsSL -o /tmp/packer.zip "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"
sudo unzip -o /tmp/packer.zip -d /usr/local/bin
rm -f /tmp/packer.zip

echo -e "\nInstallation du logiciel Ansible..."
python3 -m pip install --user ansible kubernetes PyYAML jinja2
export PATH="$HOME/.local/bin:$PATH"
ansible-galaxy collection install kubernetes.core

echo -e "\n========================================================"
echo "Séquence 3 : Déploiement de l'infrastructure"
echo "========================================================"

echo "Création de l'image Docker avec Packer..."
packer init .
packer build -var "image_tag=1.0" .
docker images | head

echo -e "\nImport de l'image Docker dans le cluster Kubernetes..."
k3d image import pra/flask-sqlite:1.0 -c pra

echo -e "\nDéploiement de l'infrastructure avec Ansible..."
ansible-playbook ansible/playbook.yml

echo -e "\nOuverture du port 8080 (port-forward en tâche de fond)..."
kubectl -n pra port-forward svc/flask 8080:80 >/tmp/web.log 2>&1 &

echo -e "\n✅ L'infrastructure est déployée !"
echo "Vous pouvez tester votre application (routes /health, /add?message=test, /count...)."
read -p "Appuyez sur [Entrée] pour lancer le Scénario 1 (PCA - Crash du pod)..."

echo -e "\n========================================================"
echo "Séquence 4 : Scénario 1 - PCA (Crash du pod)"
echo "========================================================"

# Récupération automatique du nom exact du pod Flask
POD_NAME=$(kubectl -n pra get pods --no-headers -o custom-columns=":metadata.name" | grep flask | head -n 1)

echo "Destruction du pod ciblé : $POD_NAME"
kubectl -n pra delete pod $POD_NAME

echo "Vérification de la recréation automatique du pod..."
kubectl -n pra get pods

echo "Mise à jour du port-forward pour le nouveau pod..."
pkill -f "port-forward svc/flask" || true
kubectl -n pra port-forward svc/flask 8080:80 >/tmp/web.log 2>&1 &

echo -e "\n✅ Le pod a été reconstruit. Vos données sur l'URL /consultation sont intactes."
read -p "Appuyez sur [Entrée] pour lancer le Scénario 2 (PRA - Perte du PVC)..."

echo -e "\n========================================================"
echo "Séquence 4 : Scénario 2 - PRA (Perte du PVC pra-data)"
echo "========================================================"

echo "🔥 PHASE 1 : Simulation du sinistre (Destruction de la BDD)..."
kubectl -n pra scale deployment flask --replicas=0
kubectl -n pra patch cronjob sqlite-backup -p '{"spec":{"suspend":true}}'
kubectl -n pra delete job --all
kubectl -n pra delete pvc pra-data

echo "✅ PHASE 2 : Procédure de restauration..."
kubectl apply -f k8s/

echo "Relance du port-forward temporaire (pour constater que /count est à 0)..."
pkill -f "port-forward svc/flask" || true
kubectl -n pra port-forward svc/flask 8080:80 >/tmp/web.log 2>&1 &

echo "Restauration de la BDD depuis le backup..."
kubectl apply -f pra/50-job-restore.yaml

echo "Relance des sauvegardes périodiques..."
kubectl -n pra patch cronjob sqlite-backup -p '{"spec":{"suspend":false}}'

echo -e "\n🎉 Opération terminée ! Votre environnement de production est entièrement restauré."
