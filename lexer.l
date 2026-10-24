%{
#include "parser.tab.h"
#include <string.h>
#include <stdlib.h>
%}

%%

"network"                       { return NETWORK; }
"inputs"                        { return INPUTS; }
"layer"                         { return LAYER; }
"activation"                    { return ACTIVATION; }
"relu"                          { return RELU; }
"step"                          { return STEP; }

[a-zA-Z_][a-zA-Z0-9_]*         {
                                    yylval.text = strdup(yytext);
                                    return IDENTIFIER;
                                }

"{"                             { return '{'; }
"}"                             { return '}'; }
";"                             { return ';'; }

[ \t\r\n]+                      { /* ignore whitespace */ }

.                               {
                                    printf("Unknown character: %s\n", yytext);
                                    return yytext[0];
                                }

%%

int yywrap(void)
{
    return 1;
}