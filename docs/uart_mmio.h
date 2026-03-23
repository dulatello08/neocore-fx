#ifndef NEOCOREFX_UART_MMIO_H
#define NEOCOREFX_UART_MMIO_H

#include <stdint.h>

#define NCX_UART_BASE_ADDR 0x40000000u

#define NCX_UART_TXDATA_REG  (*(volatile uint32_t *)(NCX_UART_BASE_ADDR + 0x00u))
#define NCX_UART_RXDATA_REG  (*(volatile uint32_t *)(NCX_UART_BASE_ADDR + 0x04u))
#define NCX_UART_STATUS_REG  (*(volatile uint32_t *)(NCX_UART_BASE_ADDR + 0x08u))
#define NCX_UART_CTRL_REG    (*(volatile uint32_t *)(NCX_UART_BASE_ADDR + 0x0Cu))
#define NCX_UART_BAUDDIV_REG (*(volatile uint32_t *)(NCX_UART_BASE_ADDR + 0x10u))

#define NCX_UART_STATUS_TX_READY   (1u << 0)
#define NCX_UART_STATUS_RX_VALID   (1u << 1)
#define NCX_UART_STATUS_TX_OVERRUN (1u << 2)
#define NCX_UART_STATUS_RX_OVERRUN (1u << 3)

#define NCX_UART_CTRL_TX_EN (1u << 0)
#define NCX_UART_CTRL_RX_EN (1u << 1)

static inline void ncx_uart_init(uint32_t bauddiv)
{
    NCX_UART_CTRL_REG = NCX_UART_CTRL_TX_EN | NCX_UART_CTRL_RX_EN;
    NCX_UART_BAUDDIV_REG = bauddiv;
    NCX_UART_STATUS_REG = NCX_UART_STATUS_TX_OVERRUN | NCX_UART_STATUS_RX_OVERRUN;
}

static inline void ncx_uart_putc(uint8_t c)
{
    while ((NCX_UART_STATUS_REG & NCX_UART_STATUS_TX_READY) == 0u) {
    }
    NCX_UART_TXDATA_REG = (uint32_t)c;
}

static inline uint8_t ncx_uart_getc(void)
{
    while ((NCX_UART_STATUS_REG & NCX_UART_STATUS_RX_VALID) == 0u) {
    }
    return (uint8_t)(NCX_UART_RXDATA_REG & 0xFFu);
}

static inline int ncx_uart_try_getc(uint8_t *out)
{
    if ((NCX_UART_STATUS_REG & NCX_UART_STATUS_RX_VALID) == 0u) {
        return 0;
    }
    *out = (uint8_t)(NCX_UART_RXDATA_REG & 0xFFu);
    return 1;
}

static inline void ncx_uart_puts(const char *s)
{
    while (*s != '\0') {
        if (*s == '\n') {
            ncx_uart_putc((uint8_t)'\r');
        }
        ncx_uart_putc((uint8_t)*s++);
    }
}

#endif
