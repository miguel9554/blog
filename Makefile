build:
	docker build --network=host -t blog .

run:
	docker run --network=host -v $(PWD):/app -v /app/node_modules blog
