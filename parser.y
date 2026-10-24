%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex(void);
void yyerror(const char *s);
%}

%union {
    char *text;
}

%token NETWORK
%token <text> IDENTIFIER

%%

program:
    NETWORK IDENTIFIER '{' '}'
    {
        printf("Parsed network: %s\n", $2);
        free($2);
    }
;

%%

void yyerror(const char *s)
{
    fprintf(stderr, "Parser error: %s\n", s);
}

int main(void)
{
    return yyparse();
}