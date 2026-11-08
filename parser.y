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

int input_exists(const char *name);
int find_input_index(const char *name);
int layer_exists(const char *name);
int neuron_exists_in_layer(int layer_index, const char *name);
int neuron_exists_in_current_layer(const char *name);
int get_current_layer_index(void);
int source_is_valid(const char *source_name);
void generate_llvm_ir(const char *filename);

/* ---------- Inputs ---------- */

char *input_names[MAX_INPUTS];
double input_values[MAX_INPUTS];
int input_value_set[MAX_INPUTS];

int input_count = 0;

void add_input(char *name)
{
    if (input_exists(name)) {
        fprintf(
            stderr,
            "Semantic error: input '%s' is declared more than once\n",
            name
        );

        free(name);
        exit(1);
    }

    if (input_count >= MAX_INPUTS) {
        fprintf(stderr, "Error: too many inputs\n");
        free(name);
        exit(1);
    }

    input_names[input_count] = name;
    input_values[input_count] = 0.0;
    input_value_set[input_count] = 0;

    input_count++;
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
    double output;
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

char *network_name = NULL;

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
    if (layer_exists(name)) {
        fprintf(
            stderr,
            "Semantic error: layer '%s' is declared more than once\n",
            name
        );

        free(name);
        exit(1);
    }

    if (layer_count >= MAX_LAYERS) {
        fprintf(stderr, "Error: too many layers\n");
        free(name);
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
        free(name);
        exit(1);
    }

    if (neuron_exists_in_current_layer(name)) {
        fprintf(
            stderr,
            "Semantic error: neuron '%s' is declared more than once "
            "in layer '%s'\n",
            name,
            current_layer->name
        );

        free(name);
        exit(1);
    }

    if (current_layer->neuron_count >= MAX_NEURONS) {
        fprintf(stderr, "Error: too many neurons\n");
        free(name);
        exit(1);
    }

    current_neuron =
        &current_layer->neurons[current_layer->neuron_count];

    current_neuron->name = name;
    current_neuron->connection_count = 0;
    current_neuron->bias = 0.0;
    current_neuron->output = 0.0;

    current_layer->neuron_count++;
}

void add_connection(char *source_name, double weight)
{
    if (current_neuron == NULL) {
        fprintf(stderr, "Error: connection outside neuron\n");
        free(source_name);
        exit(1);
    }

    if (!source_is_valid(source_name)) {

        int layer_index = get_current_layer_index();

        if (layer_index == 0) {
            fprintf(
                stderr,
                "Semantic error: '%s' is not a declared input "
                "for neuron '%s'\n",
                source_name,
                current_neuron->name
            );
        }
        else {
            fprintf(
                stderr,
                "Semantic error: '%s' is not a neuron "
                "in the previous layer for neuron '%s'\n",
                source_name,
                current_neuron->name
            );
        }

        free(source_name);
        exit(1);
    }

    if (current_neuron->connection_count >= MAX_CONNECTIONS) {
        fprintf(stderr, "Error: too many connections\n");
        free(source_name);
        exit(1);
    }

    Connection *connection =
        &current_neuron->connections[
            current_neuron->connection_count
        ];

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

/* ---------- Prediction Input Handling ---------- */

void set_input_value(char *name, double value)
{
    int index = find_input_index(name);

    if (index == -1) {
        fprintf(
            stderr,
            "Semantic error: '%s' is not a declared input\n",
            name
        );

        free(name);
        exit(1);
    }

    if (input_value_set[index]) {
        fprintf(
            stderr,
            "Semantic error: input '%s' was provided more than once\n",
            name
        );

        free(name);
        exit(1);
    }

    input_values[index] = value;
    input_value_set[index] = 1;

    free(name);
}

void print_prediction_inputs(void)
{
    printf("\nPrediction inputs:\n");

    for (int i = 0; i < input_count; i++) {

        if (input_value_set[i]) {
            printf(
                "  %s = %.4f\n",
                input_names[i],
                input_values[i]
            );
        }
        else {
            printf(
                "  %s = <missing>\n",
                input_names[i]
            );
        }
    }
}

/* ---------- Printing ---------- */

void print_network(char *name)
{
    printf("Parsed network: %s\n", name);

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

/* ---------- Network Execution ---------- */

double apply_activation(ActivationType activation, double value)
{
    switch (activation) {

        case ACT_RELU:
            return value > 0.0 ? value : 0.0;

        case ACT_STEP:
            return value >= 0.0 ? 1.0 : 0.0;

        default:
            return value;
    }
}

double get_source_value(int layer_index, const char *source_name)
{
    /*
     * First layer reads directly from network inputs.
     */
    if (layer_index == 0) {

        int input_index = find_input_index(source_name);

        if (input_index == -1) {
            fprintf(
                stderr,
                "Runtime error: unknown input '%s'\n",
                source_name
            );

            exit(1);
        }

        return input_values[input_index];
    }

    /*
     * Later layers read outputs from neurons
     * in the previous layer.
     */
    Layer *previous_layer = &layers[layer_index - 1];

    for (int i = 0; i < previous_layer->neuron_count; i++) {

        Neuron *neuron = &previous_layer->neurons[i];

        if (strcmp(neuron->name, source_name) == 0) {
            return neuron->output;
        }
    }

    fprintf(
        stderr,
        "Runtime error: source '%s' not found\n",
        source_name
    );

    exit(1);
}

void run_network(void)
{
    /*
     * All declared inputs must receive a value.
     */
    for (int i = 0; i < input_count; i++) {

        if (!input_value_set[i]) {
            fprintf(
                stderr,
                "Semantic error: no value provided for input '%s'\n",
                input_names[i]
            );

            exit(1);
        }
    }

    /*
     * Execute layers from first to last.
     */
    for (int i = 0; i < layer_count; i++) {

        Layer *layer = &layers[i];

        for (int j = 0; j < layer->neuron_count; j++) {

            Neuron *neuron = &layer->neurons[j];

            /*
             * A neuron's weighted sum starts with its bias.
             */
            double sum = neuron->bias;

            /*
             * Add source_value * weight for every connection.
             */
            for (int k = 0; k < neuron->connection_count; k++) {

                Connection *connection =
                    &neuron->connections[k];

                double source_value =
                    get_source_value(
                        i,
                        connection->source_name
                    );

                sum += source_value * connection->weight;
            }

            /*
             * Apply the activation assigned to the layer.
             */
            neuron->output =
                apply_activation(
                    layer->activation,
                    sum
                );
        }
    }

    /*
     * The final layer contains the prediction output.
     */
    Layer *output_layer =
        &layers[layer_count - 1];

    printf("\nPrediction:\n");

    for (int i = 0; i < output_layer->neuron_count; i++) {

        printf(
            "  %s = %.4f\n",
            output_layer->neurons[i].name,
            output_layer->neurons[i].output
        );
    }
}

void generate_llvm_ir(const char *filename)
{
    FILE *file = fopen(filename, "w");

    if (file == NULL) {
        fprintf(stderr, "Error: could not create LLVM IR file\n");
        exit(1);
    }

    /*
     * Make sure every declared input received a prediction value.
     */
    for (int i = 0; i < input_count; i++) {
        if (!input_value_set[i]) {
            fprintf(
                stderr,
                "Semantic error: no value provided for input '%s'\n",
                input_names[i]
            );

            fclose(file);
            exit(1);
        }
    }

    Layer *output_layer = &layers[layer_count - 1];

    /* ---------- LLVM Module Header ---------- */

    fprintf(file, "; PlainML generated LLVM IR\n");
    fprintf(file, "source_filename = \"plainml\"\n\n");

    fprintf(file, "declare i32 @printf(ptr, ...)\n\n");

    /*
     * "  %s = %f\\n\\0" is 11 bytes:
     * two spaces + %s + space + = + space + %f + newline + null.
     */
    fprintf(
        file,
        "@.fmt = private unnamed_addr constant "
        "[11 x i8] c\"  %%s = %%f\\0A\\00\"\n"
    );

    fprintf(
        file,
        "@.header = private unnamed_addr constant "
        "[13 x i8] c\"Prediction:\\0A\\00\"\n"
    );

    /*
     * Output-neuron names are LLVM global string constants.
     * Globals must be emitted before the main function.
     */
    for (int i = 0; i < output_layer->neuron_count; i++) {
        const char *name = output_layer->neurons[i].name;
        int name_length = (int)strlen(name) + 1;

        fprintf(
            file,
            "@.out_name_%d = private unnamed_addr constant "
            "[%d x i8] c\"%s\\00\"\n",
            i,
            name_length,
            name
        );
    }

    fprintf(file, "\n");

    /* ---------- LLVM main ---------- */

    fprintf(file, "define i32 @main() {\n");
    fprintf(file, "entry:\n");

    /*
     * Stores the LLVM register containing the output
     * of every generated neuron.
     */
    char neuron_output_registers[MAX_LAYERS][MAX_NEURONS][32];

    int register_counter = 0;

    /*
     * Generate code layer by layer.
     */
    for (int i = 0; i < layer_count; i++) {

        Layer *layer = &layers[i];

        for (int j = 0; j < layer->neuron_count; j++) {

            Neuron *neuron = &layer->neurons[j];

            char sum_register[32] = "";

            /*
             * Generate each weighted connection:
             *
             * source_value * weight
             */
            for (int k = 0; k < neuron->connection_count; k++) {

                Connection *connection =
                    &neuron->connections[k];

                char source_operand[64];

                /*
                 * First layer reads values directly from
                 * the prediction inputs in the PlainML source.
                 */
                if (i == 0) {

                    int input_index =
                        find_input_index(
                            connection->source_name
                        );

                    if (input_index == -1) {
                        fprintf(
                            stderr,
                            "LLVM generation error: "
                            "input '%s' not found\n",
                            connection->source_name
                        );

                        fclose(file);
                        exit(1);
                    }

                    snprintf(
                        source_operand,
                        sizeof(source_operand),
                        "%.17e",
                        input_values[input_index]
                    );
                }

                /*
                 * Later layers use the LLVM register produced
                 * by the referenced neuron in the previous layer.
                 */
                else {

                    int source_neuron_index = -1;

                    Layer *previous_layer =
                        &layers[i - 1];

                    for (
                        int n = 0;
                        n < previous_layer->neuron_count;
                        n++
                    ) {
                        if (
                            strcmp(
                                previous_layer->neurons[n].name,
                                connection->source_name
                            ) == 0
                        ) {
                            source_neuron_index = n;
                            break;
                        }
                    }

                    if (source_neuron_index == -1) {
                        fprintf(
                            stderr,
                            "LLVM generation error: "
                            "source neuron '%s' not found\n",
                            connection->source_name
                        );

                        fclose(file);
                        exit(1);
                    }

                    strcpy(
                        source_operand,
                        neuron_output_registers
                            [i - 1]
                            [source_neuron_index]
                    );
                }

                /*
                 * multiplication = source * weight
                 */
                char multiply_register[32];

                snprintf(
                    multiply_register,
                    sizeof(multiply_register),
                    "%%v%d",
                    register_counter++
                );

                fprintf(
                    file,
                    "  %s = fmul double %s, %.17e\n",
                    multiply_register,
                    source_operand,
                    connection->weight
                );

                /*
                 * Start the running sum with the first
                 * multiplication plus the neuron's bias.
                 */
                if (k == 0) {

                    snprintf(
                        sum_register,
                        sizeof(sum_register),
                        "%%v%d",
                        register_counter++
                    );

                    fprintf(
                        file,
                        "  %s = fadd double %s, %.17e\n",
                        sum_register,
                        multiply_register,
                        neuron->bias
                    );
                }

                /*
                 * Add all remaining weighted connections.
                 */
                else {

                    char new_sum_register[32];

                    snprintf(
                        new_sum_register,
                        sizeof(new_sum_register),
                        "%%v%d",
                        register_counter++
                    );

                    fprintf(
                        file,
                        "  %s = fadd double %s, %s\n",
                        new_sum_register,
                        sum_register,
                        multiply_register
                    );

                    strcpy(
                        sum_register,
                        new_sum_register
                    );
                }
            }

            /*
             * Apply this layer's activation function.
             */
            char compare_register[32];
            char output_register[32];

            snprintf(
                compare_register,
                sizeof(compare_register),
                "%%v%d",
                register_counter++
            );

            snprintf(
                output_register,
                sizeof(output_register),
                "%%v%d",
                register_counter++
            );

            if (layer->activation == ACT_RELU) {

                fprintf(
                    file,
                    "  %s = fcmp ogt double %s, "
                    "0.00000000000000000e+00\n",
                    compare_register,
                    sum_register
                );

                fprintf(
                    file,
                    "  %s = select i1 %s, "
                    "double %s, "
                    "double 0.00000000000000000e+00\n",
                    output_register,
                    compare_register,
                    sum_register
                );
            }

            else if (layer->activation == ACT_STEP) {

                fprintf(
                    file,
                    "  %s = fcmp oge double %s, "
                    "0.00000000000000000e+00\n",
                    compare_register,
                    sum_register
                );

                fprintf(
                    file,
                    "  %s = select i1 %s, "
                    "double 1.00000000000000000e+00, "
                    "double 0.00000000000000000e+00\n",
                    output_register,
                    compare_register
                );
            }

            /*
             * Remember which LLVM register contains this
             * neuron's output so the next layer can use it.
             */
            strcpy(
                neuron_output_registers[i][j],
                output_register
            );
        }
    }

    /* ---------- Print Final Prediction ---------- */

    fprintf(
        file,
        "  call i32 (ptr, ...) @printf(ptr @.header)\n"
    );

    for (int i = 0; i < output_layer->neuron_count; i++) {

        fprintf(
            file,
            "  call i32 (ptr, ...) "
            "@printf(ptr @.fmt, ptr @.out_name_%d, double %s)\n",
            i,
            neuron_output_registers[layer_count - 1][i]
        );
    }

    fprintf(file, "  ret i32 0\n");
    fprintf(file, "}\n");

    fclose(file);

    printf("\nGenerated LLVM IR: %s\n", filename);
}

/* ---------- Memory Cleanup ---------- */

void cleanup_network(char *name)
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

    free(name);
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
%token PREDICT
%token WITH
%token RELU
%token STEP

%token <text> IDENTIFIER
%token <number> NUMBER

%type <activation> activation_type

%%

/* ---------- Program ---------- */

program:
    network_definition predict_statement
    {
        cleanup_network(network_name);
    }
;

/* ---------- Network Definition ---------- */

network_definition:
    NETWORK IDENTIFIER '{' inputs_block layer_list '}'
    {
        network_name = $2;
        print_network(network_name);
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

/* ---------- Prediction ---------- */

predict_statement:
    PREDICT IDENTIFIER WITH '{' input_value_list '}'
    {
        if (strcmp($2, network_name) != 0) {

            fprintf(
                stderr,
                "Semantic error: network '%s' does not exist\n",
                $2
            );

            free($2);
            exit(1);
        }

        free($2);

        print_prediction_inputs();
        generate_llvm_ir("output.ll");
    }
;

input_value_list:
    input_value
    |
    input_value_list input_value
;

input_value:
    IDENTIFIER '=' NUMBER ';'
    {
        set_input_value($1, $3);
    }
;

%%

void yyerror(const char *s)
{
    fprintf(stderr, "Parser error: %s\n", s);
}

/* ---------- Semantic Checking ---------- */

int input_exists(const char *name)
{
    for (int i = 0; i < input_count; i++) {

        if (strcmp(input_names[i], name) == 0) {
            return 1;
        }
    }

    return 0;
}

int find_input_index(const char *name)
{
    for (int i = 0; i < input_count; i++) {

        if (strcmp(input_names[i], name) == 0) {
            return i;
        }
    }

    return -1;
}

int layer_exists(const char *name)
{
    for (int i = 0; i < layer_count; i++) {

        if (strcmp(layers[i].name, name) == 0) {
            return 1;
        }
    }

    return 0;
}

int neuron_exists_in_current_layer(const char *name)
{
    if (current_layer == NULL) {
        return 0;
    }

    for (int i = 0; i < current_layer->neuron_count; i++) {

        if (strcmp(current_layer->neurons[i].name, name) == 0) {
            return 1;
        }
    }

    return 0;
}

int neuron_exists_in_layer(int layer_index, const char *name)
{
    if (layer_index < 0 || layer_index >= layer_count) {
        return 0;
    }

    Layer *layer = &layers[layer_index];

    for (int i = 0; i < layer->neuron_count; i++) {

        if (strcmp(layer->neurons[i].name, name) == 0) {
            return 1;
        }
    }

    return 0;
}

int get_current_layer_index(void)
{
    if (current_layer == NULL) {
        return -1;
    }

    return (int)(current_layer - layers);
}

int source_is_valid(const char *source_name)
{
    int layer_index = get_current_layer_index();

    /*
     * First layer sources must be declared inputs.
     */
    if (layer_index == 0) {
        return input_exists(source_name);
    }

    /*
     * Later layers may use neurons from the previous layer.
     */
    if (layer_index > 0) {

        return neuron_exists_in_layer(
            layer_index - 1,
            source_name
        );
    }

    return 0;
}

int main(void)
{
    return yyparse();
}