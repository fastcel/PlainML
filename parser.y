%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_INPUTS 32

int yylex(void);
void yyerror(const char *s);

char *input_names[MAX_INPUTS];
int input_count = 0;

void add_input(char *name)
{
    if (input_count >= MAX_INPUTS) {
        fprintf(stderr, "Error: too many inputs\n");
        exit(1);
    }

    input_names[input_count++] = name;
}
%}

%union {
    char *text;
}

%token NETWORK
%token INPUTS
%token <text> IDENTIFIER

%%

program:
    NETWORK IDENTIFIER '{' inputs_block '}'
    {
        printf("Parsed network: %s\n", $2);
        printf("Inputs:\n");

        for (int i = 0; i < input_count; i++) {
            printf("  %s\n", input_names[i]);
            free(input_names[i]);
        }

        free($2);
    }
;

inputs_block:
    INPUTS '{' input_list '}'
;

input_list:
    input_decl
    |
    input_list input_decl
;

input_decl:
    IDENTIFIER ';'
    {
        add_input($1);
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