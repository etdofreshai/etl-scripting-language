#include "etl_vm.h"

#include <stdint.h>

int main(void) {
    const int8_t program[] = "ETLB1;I1;I2;I9;I4;-;*;+;R;";
    int32_t result = 0;
    int32_t status = etl_vm_run_main_i32(program, 26, &result);
    if (status != 0) {
        return 1;
    }
    if (result != 11) {
        return 2;
    }
    return 0;
}
