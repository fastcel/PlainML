%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_INPUTS 32
#define MAX_LAYERS 16

int yylex(void);
void yyerror(const char *s);

/* ---------- Inputs ---------- */

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

/* ---------- Layers ---------- */

typedef enum {
    ACT_RELU,
    ACT_STEP
} ActivationType;

typedef struct {
    char *name;
    ActivationType activation;
} Layer;

Layer layers[MAX_LAYERS];
int layer_count = 0;

void add_layer(char *name, ActivationType activation)
{
    if (layer_count >= MAX_LAYERS) {
        fprintf(stderr, "Error: too many layers\n");
        exit(1);
    }

    layers[layer_count].name = name;
    layers[layer_count].activation = activation;

    layer_count++;
}

const char *activation_name(ActivationType activation)
{
    switch (activation) {
        case ACT_RELU:
            return "relu";

        case ACT_STEP:
            return "step";

        default:
            return "unknown";
    }
}
%}

%union {
    char *text;
    int activation;
}

%token NETWORK
%token INPUTS
%token LAYER
%token ACTIVATION
%token RELU
%token STEP

%token <text> IDENTIFIER

%type <activation> activation_type

%%

program:
    NETWORK IDENTIFIER '{' inputs_block layer_list '}'
    {
        printf("Parsed network: %s\n", $2);

        printf("\nInputs:\n");

        for (int i = 0; i < input_count; i++) {
            printf("  %s\n", input_names[i]);
        }

        printf("\nLayers:\n");

        for (int i = 0; i < layer_count; i++) {
            printf(
                "  %s (activation: %s)\n",
                layers[i].name,
                activation_name(layers[i].activation)
            );
        }

        /* Free allocated identifier strings */

        for (int i = 0; i < input_count; i++) {
            free(input_names[i]);
        }

        for (int i = 0; i < layer_count; i++) {
            free(layers[i].name);
        }

        free($2);
    }
;


/* ---------- Inputs ---------- */

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


/* ---------- Layers ---------- */

layer_list:
    layer_decl
    |
    layer_list layer_decl
;

layer_decl:
    LAYER IDENTIFIER ACTIVATION activation_type '{' '}'
    {
        add_layer($2, $4);
    }
;

activation_type:
    RELU
    {
        $$ = ACT_RELU;
    }
    |
    STEP
    {
        $$ = ACT_STEP;
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