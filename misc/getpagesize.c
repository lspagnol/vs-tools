#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
        int page_size = getpagesize();
        printf("The page size is %d\n", page_size);
        exit(0);
}
