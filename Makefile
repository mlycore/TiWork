build:
	kubectl create ns endgame 
	kubectl create configmap tidb-init -n endgame --from-file=init.sql
	kubectl apply -f pd-peer-service.yaml  
	kubectl apply -f pd-service.yaml  
	kubectl apply -f pd-statefulset.yaml  
	kubectl apply -f tikv-peer-service.yaml  
	kubectl apply -f tikv-statefulset.yaml
#	kubectl apply -f tidb-peer-svc.yaml  
	kubectl apply -f tidb-service.yaml  
	#kubectl apply -f tidb-statefulset.yaml  
	kubectl apply -f tidb-deployment.yaml  
	kubectl apply -f tidb-init-job.yaml  
clean:
	kubectl delete ns test4
