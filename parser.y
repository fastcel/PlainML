%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_INPUTS 32
#define MAX_LAYERS 16
#define MAX_NEURONS 32
#define MAX_CONNECTIONS 32

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

/* ---------- Neural Network Structures ---------- */

typedef enum {
    ACT_RELU,
    ACT_STEP
} ActivationType;

typedef struct {
    char *source_name;
    double weight;
} Connection;

typedef struct {
    char *name;

    Connection connections[MAX_CONNECTIONS];
    int connection_count;

    double bias;
} Neuron;

typedef struct {
    char *name;
    ActivationType activation;

    Neuron neurons[MAX_NEURONS];
    int neuron_count;
} Layer;

/* ---------- Stored Network ---------- */

Layer layers[MAX_LAYERS];
int layer_count = 0;

Layer *current_layer = NULL;
Neuron *current_neuron = NULL;

/* ---------- Helper Functions ---------- */

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

void start_layer(char *name, ActivationType activation)
{
    if (layer_count >= MAX_LAYERS) {
        fprintf(stderr, "Error: too many layers\n");
        exit(1);
    }

    current_layer = &layers[layer_count];

    current_layer->name = name;
    current_layer->activation = activation;
    current_layer->neuron_count = 0;

    layer_count++;
}

void start_neuron(char *name)
{
    if (current_layer == NULL) {
        fprintf(stderr, "Error: neuron outside layer\n");
        exit(1);
    }

    if (current_layer->neuron_count >= MAX_NEURONS) {
        fprintf(stderr, "Error: too many neurons\n");
        exit(1);
    }

    current_neuron =
        &current_layer->neurons[current_layer->neuron_count];

    current_neuron->name = name;
    current_neuron->connection_count = 0;
    current_neuron->bias = 0.0;

    current_layer->neuron_count++;
}

void add_connection(char *source_name, double weight)
{
    if (current_neuron == NULL) {
        fprintf(stderr, "Error: connection outside neuron\n");
        exit(1);
    }

    if (current_neuron->connection_count >= MAX_CONNECTIONS) {
        fprintf(stderr, "Error: too many connections\n");
        exit(1);
    }

    Connection *connection =
        &current_neuron->connections[current_neuron->connection_count];

    connection->source_name = source_name;
    connection->weight = weight;

    current_neuron->connection_count++;
}

void set_bias(double bias)
{
    if (current_neuron == NULL) {
        fprintf(stderr, "Error: bias outside neuron\n");
        exit(1);
    }

    current_neuron->bias = bias;
}

/* ---------- Printing ---------- */

void print_network(char *network_name)
{
    printf("Parsed network: %s\n", network_name);

    printf("\nInputs:\n");

    for (int i = 0; i < input_count; i++) {
        printf("  %s\n", input_names[i]);
    }

    printf("\nLayers:\n");

    for (int i = 0; i < layer_count; i++) {

        Layer *layer = &layers[i];

        printf(
            "\nLayer: %s (activation: %s)\n",
            layer->name,
            activation_name(layer->activation)
        );

        for (int j = 0; j < layer->neuron_count; j++) {

            Neuron *neuron = &layer->neurons[j];

            printf("  Neuron: %s\n", neuron->name);

            for (int k = 0; k < neuron->connection_count; k++) {

                Connection *connection =
                    &neuron->connections[k];

                printf(
                    "    %s weight %.2f\n",
                    connection->source_name,
                    connection->weight
                );
            }

            printf("    bias %.2f\n", neuron->bias);
        }
    }
}

/* ---------- Memory Cleanup ---------- */

void cleanup_network(char *network_name)
{
    for (int i = 0; i < input_count; i++) {
        free(input_names[i]);
    }

    for (int i = 0; i < layer_count; i++) {

        Layer *layer = &layers[i];

        for (int j = 0; j < layer->neuron_count; j++) {

            Neuron *neuron = &layer->neurons[j];

            for (int k = 0; k < neuron->connection_count; k++) {
                free(neuron->connections[k].source_name);
            }

            free(neuron->name);
        }

        free(layer->name);
    }

    free(network_name);
}

%}

/* ---------- Semantic Values ---------- */

%union {
    char *text;
    int activation;
    double number;
}

/* ---------- Tokens ---------- */

%token NETWORK
%token INPUTS
%token LAYER
%token ACTIVATION
%token NEURON
%token WEIGHT
%token BIAS
%token RELU
%token STEP

%token <text> IDENTIFIER
%token <number> NUMBER

%type <activation> activation_type

%%

/* ---------- Program ---------- */

program:
    NETWORK IDENTIFIER '{' inputs_block layer_list '}'
    {
        print_network($2);
        cleanup_network($2);
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
    layer_header '{' neuron_list '}'
    {
        current_layer = NULL;
    }
;

layer_header:
    LAYER IDENTIFIER ACTIVATION activation_type
    {
        start_layer($2, $4);
    }
;

/* ---------- Activation Functions ---------- */

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

/* ---------- Neurons ---------- */

neuron_list:
    neuron_decl
    |
    neuron_list neuron_decl
;

neuron_decl:
    neuron_header '{' neuron_body '}'
    {
        current_neuron = NULL;
    }
;

neuron_header:
    NEURON IDENTIFIER
    {
        start_neuron($2);
    }
;

/* ---------- Neuron Body ---------- */

neuron_body:
    connection_list bias_decl
;

connection_list:
    connection_decl
    |
    connection_list connection_decl
;

connection_decl:
    IDENTIFIER WEIGHT NUMBER ';'
    {
        add_connection($1, $3);
    }
;

bias_decl:
    BIAS NUMBER ';'
    {
        set_bias($2);
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