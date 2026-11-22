#include <stdio.h>
#include <stdlib.h>

#include "mojoshader.h"

enum { MaxShaderBytes = 128 * 1024 };

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        fprintf(stderr, "usage: d3d9-to-msl function-name < shader-bytecode\n");
        return EXIT_FAILURE;
    }

    unsigned char tokens[MaxShaderBytes + 1];
    const size_t size = fread(tokens, 1, sizeof(tokens), stdin);
    if (ferror(stdin) || size < 8 || size > MaxShaderBytes || size % 4 != 0)
    {
        fprintf(stderr, "Invalid shader bytecode size: %zu\n", size);
        return EXIT_FAILURE;
    }

    const MOJOSHADER_parseData *shader = MOJOSHADER_parse(
        MOJOSHADER_PROFILE_METAL, argv[1], tokens, (unsigned int)size,
        NULL, 0, NULL, 0, NULL, NULL, NULL);
    int result = EXIT_FAILURE;
    if (shader->error_count == 0 && shader->output_len > 0)
    {
        const size_t length = (size_t)shader->output_len;
        if (fwrite(shader->output, 1, length, stdout) == length && fflush(stdout) == 0)
            result = EXIT_SUCCESS;
    }
    else
    {
        for (int i = 0; i < shader->error_count; ++i)
            fprintf(stderr, "%s\n", shader->errors[i].error);
    }

    MOJOSHADER_freeParseData(shader);
    return result;
}
