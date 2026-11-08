.PHONY: plainml aot run-aot test test-aot test-errors clean

plainml: parser.tab.c lex.yy.c
	gcc parser.tab.c lex.yy.c -o plainml -lfl

parser.tab.c parser.tab.h: parser.y
	bison -d parser.y

lex.yy.c: lexer.l parser.tab.h
	flex lexer.l

aot: plainml
	@if [ -z "$(SOURCE)" ]; then \
		echo "Usage: make aot SOURCE=examples/test.plain"; \
		exit 1; \
	fi
	./plainml < $(SOURCE)
	clang output.ll -o plainml_aot
	@echo "AOT executable created: plainml_aot"

run-aot:
	./plainml_aot

test: test-aot test-errors

test-aot: plainml
	@set -e; \
	for f in examples/test.plain examples/multi_neuron.plain examples/deep_network.plain; do \
		echo "===== Testing $$f ====="; \
		./plainml < $$f; \
		clang output.ll -o plainml_aot; \
		./plainml_aot; \
		echo; \
	done

test-errors: plainml
	@set -e; \
	for f in \
		examples/errors/unknown_input.plain \
		examples/errors/missing_prediction_input.plain \
		examples/errors/duplicate_prediction_input.plain \
		examples/errors/duplicate_input_decl.plain \
		examples/errors/duplicate_layer.plain \
		examples/errors/duplicate_neuron.plain; do \
		echo "===== Expecting failure: $$f ====="; \
		if ./plainml < $$f; then \
			echo "ERROR: $$f should have failed"; \
			exit 1; \
		else \
			echo "Correctly rejected $$f"; \
		fi; \
		echo; \
	done

clean:
	rm -f plainml parser.tab.c parser.tab.h lex.yy.c output.ll plainml_aot