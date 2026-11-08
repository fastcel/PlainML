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

clean:
	rm -f plainml parser.tab.c parser.tab.h lex.yy.c output.ll plainml_aot