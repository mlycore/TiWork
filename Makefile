build:
	kubectl create ns endgame 
	kubectl create configmap tidb-init -n endgame --from-file=init.sql
	kubectl apply -f pd-peer-svc.yaml  
	kubectl apply -f pd-svc.yaml  
	kubectl apply -f pd-sts.yaml  
	kubectl apply -f tikv-peer-svc.yaml  
	kubectl apply -f tikv-sts.yaml
#	kubectl apply -f tidb-peer-svc.yaml  
	kubectl apply -f tidb-svc.yaml  
	kubectl apply -f tidb-sts.yaml  
	kubectl apply -f tidb-init-job.yaml  
clean:
	kubectl delete ns test4
