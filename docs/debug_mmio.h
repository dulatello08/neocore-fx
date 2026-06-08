#ifndef NEOCOREFX_DEBUG_MMIO_H
#define NEOCOREFX_DEBUG_MMIO_H

#include <stdint.h>

#define NCX_DEBUG_BASE_ADDR 0x40000300u
#define NCX_DEBUG_ID_VALUE 0x4E434442u /* "NCDB" */
#define NCX_DEBUG_CAPS_VALUE 0x0000003Fu

#define NCX_DEBUG_ID_REG              (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x00u))
#define NCX_DEBUG_CAPS_REG            (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x04u))
#define NCX_DEBUG_CTRL_REG            (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x08u))
#define NCX_DEBUG_STATUS_REG          (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x0Cu))
#define NCX_DEBUG_PC_REG              (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x10u))
#define NCX_DEBUG_CAUSE_REG           (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x14u))
#define NCX_DEBUG_GPR_IDX_REG         (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x18u))
#define NCX_DEBUG_GPR_RDATA_REG       (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x1Cu))
#define NCX_DEBUG_GPR_WDATA_REG       (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x20u))
#define NCX_DEBUG_GPR_CMD_REG         (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x24u))
#define NCX_DEBUG_MEM_ADDR_REG        (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x28u))
#define NCX_DEBUG_MEM_WDATA_REG       (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x2Cu))
#define NCX_DEBUG_MEM_RDATA_REG       (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x30u))
#define NCX_DEBUG_MEM_CMD_REG         (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x34u))
#define NCX_DEBUG_MEM_STATUS_REG      (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x38u))
#define NCX_DEBUG_CYCLE_COUNT_REG     (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x40u))
#define NCX_DEBUG_RETIRE_COUNT_REG    (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x44u))
#define NCX_DEBUG_REDIRECT_COUNT_REG  (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x48u))
#define NCX_DEBUG_LOAD_STALL_COUNT_REG (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x4Cu))
#define NCX_DEBUG_MEM_STALL_COUNT_REG (*(volatile uint32_t *)(NCX_DEBUG_BASE_ADDR + 0x50u))

#define NCX_DEBUG_CTRL_HALT_REQ   (1u << 0)
#define NCX_DEBUG_CTRL_RESUME_REQ (1u << 1)
#define NCX_DEBUG_CTRL_STEP_REQ   (1u << 2)

#define NCX_DEBUG_STATUS_HALTED_BIT      0
#define NCX_DEBUG_STATUS_HALT_REASON_LSB 4
#define NCX_DEBUG_STATUS_HALT_REASON_MSK (0x7u << NCX_DEBUG_STATUS_HALT_REASON_LSB)
#define NCX_DEBUG_STATUS_LAST_FAULT_BIT  7

#define NCX_DEBUG_GPR_CMD_WRITE (1u << 1)

#define NCX_DEBUG_MEM_CMD_READ       (1u << 0)
#define NCX_DEBUG_MEM_CMD_WRITE      (1u << 1)
#define NCX_DEBUG_MEM_CMD_SIZE_LSB   2
#define NCX_DEBUG_MEM_CMD_SIZE_MSK   (0x3u << NCX_DEBUG_MEM_CMD_SIZE_LSB)
#define NCX_DEBUG_MEM_SIZE_BYTE      0u
#define NCX_DEBUG_MEM_SIZE_HALF      1u
#define NCX_DEBUG_MEM_SIZE_WORD      2u

#define NCX_DEBUG_MEM_STATUS_BUSY_BIT    0
#define NCX_DEBUG_MEM_STATUS_DONE_BIT    1
#define NCX_DEBUG_MEM_STATUS_ERR_BIT     2
#define NCX_DEBUG_MEM_STATUS_TIMEOUT_BIT 3
#define NCX_DEBUG_MEM_STATUS_HALTED_BIT  4

static inline void ncx_debug_halt(void)
{
    NCX_DEBUG_CTRL_REG = NCX_DEBUG_CTRL_HALT_REQ;
}

static inline void ncx_debug_resume(void)
{
    NCX_DEBUG_CTRL_REG = NCX_DEBUG_CTRL_RESUME_REQ;
}

static inline void ncx_debug_step(void)
{
    NCX_DEBUG_CTRL_REG = NCX_DEBUG_CTRL_STEP_REQ;
}

static inline void ncx_debug_set_pc(uint32_t pc)
{
    NCX_DEBUG_PC_REG = pc & ~0x3u;
}

static inline uint32_t ncx_debug_read_gpr(uint32_t idx)
{
    NCX_DEBUG_GPR_IDX_REG = idx & 0xFu;
    return NCX_DEBUG_GPR_RDATA_REG;
}

static inline void ncx_debug_write_gpr(uint32_t idx, uint32_t value)
{
    NCX_DEBUG_GPR_IDX_REG = idx & 0xFu;
    NCX_DEBUG_GPR_WDATA_REG = value;
    NCX_DEBUG_GPR_CMD_REG = NCX_DEBUG_GPR_CMD_WRITE;
}

#endif
