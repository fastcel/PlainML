plainml: parser.tab.c lex.yy.c
	gcc parser.tab.c lex.yy.c -o plainml -lfl

parser.tab.c parser.tab.h: parser.y
	bison -d parser.y

lex.yy.c: lexer.l parser.tab.h
	flex lexer.l

clean:
	rm -f plainml parser.tab.c parser.tab.h lex.yy.c