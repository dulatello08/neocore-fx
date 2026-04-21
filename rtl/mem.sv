//
// mem.sv
// NeoCoreFX - Memory subsystem fabric (BRAM + UART MMIO + DEBUG MMIO)
//

module mem (
    // Clock/reset controls.
    input  logic        clk,
    input  logic        rst,

    // I-Bus read-only port.
    input  logic        ibus_cyc,
    input  logic        ibus_stb,
    input  logic [31:0] ibus_addr,
    output logic        ibus_ack,
    output logic [31:0] ibus_rdata,
    output logic        ibus_err,

    // D-Bus read/write port from core BIU.
    input  logic        dbus_cyc,
    input  logic        dbus_stb,
    input  logic        dbus_we,
    input  logic [31:0] dbus_addr,
    input  logic [31:0] dbus_wdata,
    input  logic [3:0]  dbus_sel,
    output logic        dbus_ack,
    output logic [31:0] dbus_rdata,
    output logic        dbus_err,
    input  logic        debug_enable_i,

    // Core debug status in.
    input  logic        core_halted_i,
    input  logic [31:0] core_current_pc_i,
    input  logic [2:0]  core_halt_reason_i,
    input  logic        core_last_fault_i,
    input  logic [31:0] core_last_fault_pc_i,
    input  logic [31:0] core_last_fault_addr_i,
    input  logic [31:0] core_last_illegal_inst_i,
    input  logic [31:0] core_cycle_count_i,
    input  logic [31:0] core_retire_count_i,
    input  logic [31:0] core_redirect_count_i,
    input  logic [31:0] core_load_stall_count_i,
    input  logic [31:0] core_mem_stall_count_i,

    // Debug control out to core.
    output logic        dbg_halt_req_o,
    output logic        dbg_resume_req_o,
    output logic        dbg_step_req_o,
    output logic [3:0]  dbg_gpr_addr_o,
    input  logic [31:0] dbg_gpr_rdata_i,
    output logic        dbg_gpr_we_o,
    output logic [31:0] dbg_gpr_wdata_o,

    // SoC UART pins.
    input  logic        uart_rx_i,
    output logic        uart_tx_o
);
    timeunit 1ns;
    timeprecision 1ps;

    import mem_pkg::*;

    localparam logic [1:0] SIZE_BYTE = 2'b00;
    localparam logic [1:0] SIZE_HALF = 2'b01;
    localparam logic [1:0] SIZE_WORD = 2'b10;

    // -------------------------------------------------------------------------
    // Core-side request decode
    // -------------------------------------------------------------------------
    logic core_req_valid;
    logic core_sel_bram;
    logic core_sel_uart;
    logic core_sel_debug;
    logic core_decode_err;

    assign core_req_valid = dbus_cyc & dbus_stb;

    // -------------------------------------------------------------------------
    // Debug MMIO block wires
    // -------------------------------------------------------------------------
    logic debugmmio_req;
    logic debugmmio_we;
    logic [31:0] debugmmio_addr;
    logic [31:0] debugmmio_wdata;
    logic [3:0]  debugmmio_sel;
    logic debugmmio_ack;
    logic [31:0] debugmmio_rdata;
    logic debugmmio_err;

    logic mmio_halt_req;
    logic mmio_resume_req;
    logic mmio_step_req;
    logic [3:0] mmio_gpr_addr;
    logic mmio_gpr_we;
    logic [31:0] mmio_gpr_wdata;

    logic mmio_dbg_mem_req;
    logic mmio_dbg_mem_we;
    logic [1:0] mmio_dbg_mem_size;
    logic [31:0] mmio_dbg_mem_addr;
    logic [31:0] mmio_dbg_mem_wdata;
    logic mmio_dbg_mem_done;
    logic [31:0] mmio_dbg_mem_rdata;
    logic mmio_dbg_mem_err;

    // -------------------------------------------------------------------------
    // UART debug agent wires
    // -------------------------------------------------------------------------
    logic uart_dbg_req;
    logic uart_dbg_we;
    logic [31:0] uart_dbg_addr;
    logic [31:0] uart_dbg_wdata;
    logic [3:0]  uart_dbg_sel;
    logic uart_dbg_ack;
    logic [31:0] uart_dbg_rdata;
    logic uart_dbg_err;

    logic uart_debug_active;
    logic uart_debug_active_eff;

    logic uart_halt_req;
    logic uart_resume_req;
    logic uart_step_req;
    logic [3:0] uart_gpr_addr;
    logic uart_gpr_we;
    logic [31:0] uart_gpr_wdata;

    logic uart_dbg_mem_req;
    logic uart_dbg_mem_we;
    logic [1:0] uart_dbg_mem_size;
    logic [31:0] uart_dbg_mem_addr;
    logic [31:0] uart_dbg_mem_wdata;
    logic uart_dbg_mem_done;
    logic [31:0] uart_dbg_mem_rdata;
    logic uart_dbg_mem_err;

    // -------------------------------------------------------------------------
    // Shared downstream D-channel after arbitration
    // -------------------------------------------------------------------------
    logic m_req;
    logic m_we;
    logic [31:0] m_addr;
    logic [31:0] m_wdata;
    logic [3:0]  m_sel;

    logic m_sel_bram;
    logic m_sel_uart;
    logic m_sel_debug;
    logic m_decode_err;

    logic bram_dbus_ack;
    logic [31:0] bram_dbus_rdata;
    logic bram_dbus_err;

    logic uart_console_ack;
    logic [31:0] uart_console_rdata;
    logic uart_console_err;

    logic uart_phy_ack;
    logic [31:0] uart_phy_rdata;
    logic uart_phy_err;

    logic uart_console_rx_valid;
    logic [7:0] uart_console_rx_data;
    logic uart_console_rx_ready;
    logic uart_console_tx_valid;
    logic [7:0] uart_console_tx_data;
    logic uart_console_tx_ready;

    logic source_core_q;
    logic source_mmio_dbg_q;
    logic source_uart_dbg_q;

    logic core_decode_err_q;
    logic mmio_dbg_decode_err_q;
    logic uart_dbg_decode_err_q;

    // -------------------------------------------------------------------------
    // Helpers: map debug-master size/address into BIU-style sel/wdata lanes.
    // -------------------------------------------------------------------------
    function automatic logic [3:0] d_gen_sel(input logic [1:0] size, input logic [1:0] lsb);
        case (size)
            SIZE_BYTE: begin
                case (lsb)
                    2'b00: return 4'b1000;
                    2'b01: return 4'b0100;
                    2'b10: return 4'b0010;
                    default: return 4'b0001;
                endcase
            end
            SIZE_HALF: begin
                case (lsb)
                    2'b00: return 4'b1100;
                    2'b10: return 4'b0011;
                    default: return 4'b0000;
                endcase
            end
            default: return 4'b1111;
        endcase
    endfunction

    function automatic logic [31:0] d_gen_wdata(
        input logic [1:0]  size,
        input logic [1:0]  lsb,
        input logic [31:0] data
    );
        case (size)
            SIZE_BYTE: begin
                case (lsb)
                    2'b00: return {data[7:0], 24'h000000};
                    2'b01: return {8'h00, data[7:0], 16'h0000};
                    2'b10: return {16'h0000, data[7:0], 8'h00};
                    default: return {24'h000000, data[7:0]};
                endcase
            end
            SIZE_HALF: begin
                case (lsb)
                    2'b00: return {data[15:0], 16'h0000};
                    2'b10: return {16'h0000, data[15:0]};
                    default: return 32'h0000_0000;
                endcase
            end
            default: return data;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Debug control merge into core-facing outputs.
    // UART-agent path has priority while active/owned.
    // -------------------------------------------------------------------------
    assign uart_debug_active_eff = debug_enable_i ? uart_debug_active : 1'b0;

    assign dbg_halt_req_o = mmio_halt_req || (debug_enable_i && uart_halt_req);
    assign dbg_resume_req_o = mmio_resume_req || (debug_enable_i && uart_resume_req);
    assign dbg_step_req_o = mmio_step_req || (debug_enable_i && uart_step_req);

    assign dbg_gpr_addr_o = uart_debug_active_eff ? uart_gpr_addr : mmio_gpr_addr;
    assign dbg_gpr_we_o = mmio_gpr_we || (debug_enable_i && uart_gpr_we);
    assign dbg_gpr_wdata_o = (debug_enable_i && uart_gpr_we) ? uart_gpr_wdata : mmio_gpr_wdata;

    // -------------------------------------------------------------------------
    // Core decode regions.
    // -------------------------------------------------------------------------
    assign core_sel_bram = core_req_valid && mem_addr_in_range(dbus_addr);
    assign core_sel_uart = core_req_valid && uart_addr_in_range(dbus_addr);
    assign core_sel_debug = core_req_valid && debug_addr_in_range(dbus_addr);
    assign core_decode_err = core_req_valid && !core_sel_bram && !core_sel_uart && !core_sel_debug;

    // -------------------------------------------------------------------------
    // Debug master arbitration (only while core halted).
    // Priority: UART debug agent > MMIO debug block.
    // -------------------------------------------------------------------------
    logic grant_uart_dbg;
    logic grant_mmio_dbg;

    assign grant_uart_dbg = core_halted_i && debug_enable_i && uart_dbg_mem_req;
    assign grant_mmio_dbg = core_halted_i && !grant_uart_dbg && mmio_dbg_mem_req;

    // -------------------------------------------------------------------------
    // Shared downstream request mux.
    // Core traffic always takes precedence over debug masters.
    // -------------------------------------------------------------------------
    always_comb begin
        m_req = 1'b0;
        m_we = 1'b0;
        m_addr = 32'h0000_0000;
        m_wdata = 32'h0000_0000;
        m_sel = 4'b0000;

        if (core_req_valid) begin
            m_req = 1'b1;
            m_we = dbus_we;
            m_addr = dbus_addr;
            m_wdata = dbus_wdata;
            m_sel = dbus_sel;
        end else if (grant_uart_dbg) begin
            m_req = 1'b1;
            m_we = uart_dbg_mem_we;
            m_addr = uart_dbg_mem_addr;
            m_wdata = d_gen_wdata(uart_dbg_mem_size, uart_dbg_mem_addr[1:0], uart_dbg_mem_wdata);
            m_sel = d_gen_sel(uart_dbg_mem_size, uart_dbg_mem_addr[1:0]);
        end else if (grant_mmio_dbg) begin
            m_req = 1'b1;
            m_we = mmio_dbg_mem_we;
            m_addr = mmio_dbg_mem_addr;
            m_wdata = d_gen_wdata(mmio_dbg_mem_size, mmio_dbg_mem_addr[1:0], mmio_dbg_mem_wdata);
            m_sel = d_gen_sel(mmio_dbg_mem_size, mmio_dbg_mem_addr[1:0]);
        end
    end

    assign m_sel_bram = m_req && mem_addr_in_range(m_addr);
    assign m_sel_uart = core_sel_uart;
    assign m_sel_debug = core_sel_debug;
    assign m_decode_err = m_req && !m_sel_bram && !m_sel_uart && !m_sel_debug;

    // -------------------------------------------------------------------------
    // Track source ownership for response routing.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            source_core_q <= 1'b0;
            source_mmio_dbg_q <= 1'b0;
            source_uart_dbg_q <= 1'b0;
            core_decode_err_q <= 1'b0;
            mmio_dbg_decode_err_q <= 1'b0;
            uart_dbg_decode_err_q <= 1'b0;
        end else begin
            source_core_q <= core_req_valid;
            source_mmio_dbg_q <= !core_req_valid && grant_mmio_dbg;
            source_uart_dbg_q <= !core_req_valid && grant_uart_dbg;

            core_decode_err_q <= core_req_valid && core_decode_err;
            mmio_dbg_decode_err_q <= !core_req_valid && grant_mmio_dbg && m_decode_err;
            uart_dbg_decode_err_q <= !core_req_valid && grant_uart_dbg && m_decode_err;
        end
    end

    // -------------------------------------------------------------------------
    // BRAM slave
    // -------------------------------------------------------------------------
    mem_bram u_bram (
        .clk        (clk),
        .rst        (rst),
        .ibus_cyc   (ibus_cyc),
        .ibus_stb   (ibus_stb),
        .ibus_addr  (ibus_addr),
        .ibus_ack   (ibus_ack),
        .ibus_rdata (ibus_rdata),
        .ibus_err   (ibus_err),
        .dbus_cyc   (m_sel_bram),
        .dbus_stb   (m_sel_bram),
        .dbus_we    (m_we),
        .dbus_addr  (m_addr),
        .dbus_wdata (m_wdata),
        .dbus_sel   (m_sel),
        .dbus_ack   (bram_dbus_ack),
        .dbus_rdata (bram_dbus_rdata),
        .dbus_err   (bram_dbus_err)
    );

    // -------------------------------------------------------------------------
    // Debug MMIO block (core software-visible path)
    // -------------------------------------------------------------------------
    assign debugmmio_req = m_sel_debug;
    assign debugmmio_we = m_we;
    assign debugmmio_addr = m_addr;
    assign debugmmio_wdata = m_wdata;
    assign debugmmio_sel = m_sel;

    debug_mmio u_debug_mmio (
        .clk                    (clk),
        .rst                    (rst),
        .req_i                  (debugmmio_req),
        .we_i                   (debugmmio_we),
        .addr_i                 (debugmmio_addr),
        .wdata_i                (debugmmio_wdata),
        .sel_i                  (debugmmio_sel),
        .ack_o                  (debugmmio_ack),
        .rdata_o                (debugmmio_rdata),
        .err_o                  (debugmmio_err),
        .core_halted_i          (core_halted_i),
        .core_halt_reason_i     (core_halt_reason_i),
        .core_pc_i              (core_current_pc_i),
        .core_last_fault_i      (core_last_fault_i),
        .core_last_fault_pc_i   (core_last_fault_pc_i),
        .core_last_fault_addr_i (core_last_fault_addr_i),
        .core_last_illegal_inst_i(core_last_illegal_inst_i),
        .halt_req_o             (mmio_halt_req),
        .resume_req_o           (mmio_resume_req),
        .step_req_o             (mmio_step_req),
        .gpr_addr_o             (mmio_gpr_addr),
        .gpr_rdata_i            (dbg_gpr_rdata_i),
        .gpr_we_o               (mmio_gpr_we),
        .gpr_wdata_o            (mmio_gpr_wdata),
        .cycle_count_i          (core_cycle_count_i),
        .retire_count_i         (core_retire_count_i),
        .branch_redirect_count_i(core_redirect_count_i),
        .load_stall_count_i     (core_load_stall_count_i),
        .mem_stall_count_i      (core_mem_stall_count_i),
        .dbg_mem_req_o          (mmio_dbg_mem_req),
        .dbg_mem_we_o           (mmio_dbg_mem_we),
        .dbg_mem_size_o         (mmio_dbg_mem_size),
        .dbg_mem_addr_o         (mmio_dbg_mem_addr),
        .dbg_mem_wdata_o        (mmio_dbg_mem_wdata),
        .dbg_mem_done_i         (mmio_dbg_mem_done),
        .dbg_mem_rdata_i        (mmio_dbg_mem_rdata),
        .dbg_mem_err_i          (mmio_dbg_mem_err)
    );

    // -------------------------------------------------------------------------
    // UART debug agent
    // -------------------------------------------------------------------------
    debug_uart_agent u_debug_uart_agent (
        .clk                    (clk),
        .rst                    (rst),
        .uart_req_o             (uart_dbg_req),
        .uart_we_o              (uart_dbg_we),
        .uart_addr_o            (uart_dbg_addr),
        .uart_wdata_o           (uart_dbg_wdata),
        .uart_sel_o             (uart_dbg_sel),
        .uart_ack_i             (debug_enable_i ? uart_dbg_ack : 1'b0),
        .uart_rdata_i           (debug_enable_i ? uart_dbg_rdata : 32'h0000_0000),
        .uart_err_i             (debug_enable_i ? uart_dbg_err : 1'b0),
        .core_halted_i          (core_halted_i),
        .core_halt_reason_i     (core_halt_reason_i),
        .core_pc_i              (core_current_pc_i),
        .core_last_fault_i      (core_last_fault_i),
        .core_last_fault_pc_i   (core_last_fault_pc_i),
        .core_last_fault_addr_i (core_last_fault_addr_i),
        .core_last_illegal_inst_i(core_last_illegal_inst_i),
        .halt_req_o             (uart_halt_req),
        .resume_req_o           (uart_resume_req),
        .step_req_o             (uart_step_req),
        .gpr_addr_o             (uart_gpr_addr),
        .gpr_rdata_i            (dbg_gpr_rdata_i),
        .gpr_we_o               (uart_gpr_we),
        .gpr_wdata_o            (uart_gpr_wdata),
        .cycle_count_i          (core_cycle_count_i),
        .retire_count_i         (core_retire_count_i),
        .branch_redirect_count_i(core_redirect_count_i),
        .load_stall_count_i     (core_load_stall_count_i),
        .mem_stall_count_i      (core_mem_stall_count_i),
        .dbg_mem_req_o          (uart_dbg_mem_req),
        .dbg_mem_we_o           (uart_dbg_mem_we),
        .dbg_mem_size_o         (uart_dbg_mem_size),
        .dbg_mem_addr_o         (uart_dbg_mem_addr),
        .dbg_mem_wdata_o        (uart_dbg_mem_wdata),
        .dbg_mem_done_i         (uart_dbg_mem_done),
        .dbg_mem_rdata_i        (uart_dbg_mem_rdata),
        .dbg_mem_err_i          (uart_dbg_mem_err),
        .fw_rx_valid_o          (uart_console_rx_valid),
        .fw_rx_data_o           (uart_console_rx_data),
        .fw_rx_ready_i          (debug_enable_i ? uart_console_rx_ready : 1'b0),
        .fw_tx_valid_i          (debug_enable_i ? uart_console_tx_valid : 1'b0),
        .fw_tx_data_i           (uart_console_tx_data),
        .fw_tx_ready_o          (uart_console_tx_ready),
        .uart_debug_owned_o     (),
        .debug_active_o         (uart_debug_active)
    );

    // -------------------------------------------------------------------------
    // Firmware-facing virtual UART endpoint.
    // -------------------------------------------------------------------------
    uart_mmio #(
        .STREAM_MODE(1'b1)
    ) u_uart_console (
        .clk        (clk),
        .rst        (rst),
        .req_i      (m_sel_uart),
        .we_i       (m_we),
        .addr_i     (m_addr),
        .wdata_i    (m_wdata),
        .sel_i      (m_sel),
        .ack_o      (uart_console_ack),
        .rdata_o    (uart_console_rdata),
        .err_o      (uart_console_err),
        .uart_rx_i  (1'b1),
        .uart_tx_o  (),
        .stream_rx_valid_i(debug_enable_i ? uart_console_rx_valid : 1'b0),
        .stream_rx_data_i (uart_console_rx_data),
        .stream_rx_ready_o(uart_console_rx_ready),
        .stream_tx_valid_o(uart_console_tx_valid),
        .stream_tx_data_o (uart_console_tx_data),
        .stream_tx_ready_i(debug_enable_i ? uart_console_tx_ready : 1'b0)
    );

    // -------------------------------------------------------------------------
    // Physical UART endpoint owned by ncdb.
    // -------------------------------------------------------------------------
    uart_mmio #(
        .STREAM_MODE(1'b0)
    ) u_uart_phy (
        .clk        (clk),
        .rst        (rst),
        .req_i      (debug_enable_i && uart_dbg_req),
        .we_i       (uart_dbg_we),
        .addr_i     (uart_dbg_addr),
        .wdata_i    (uart_dbg_wdata),
        .sel_i      (uart_dbg_sel),
        .ack_o      (uart_phy_ack),
        .rdata_o    (uart_phy_rdata),
        .err_o      (uart_phy_err),
        .uart_rx_i  (uart_rx_i),
        .uart_tx_o  (uart_tx_o),
        .stream_rx_valid_i(1'b0),
        .stream_rx_data_i (8'h00),
        .stream_rx_ready_o(),
        .stream_tx_valid_o(),
        .stream_tx_data_o (),
        .stream_tx_ready_i(1'b0)
    );

    assign uart_dbg_ack = uart_phy_ack;
    assign uart_dbg_rdata = uart_phy_rdata;
    assign uart_dbg_err = uart_phy_err;

    // -------------------------------------------------------------------------
    // Shared response routing.
    // -------------------------------------------------------------------------
    logic m_ack;
    logic [31:0] m_rdata;
    logic m_err;

    always_comb begin
        m_ack = 1'b0;
        m_rdata = 32'h0000_0000;
        m_err = 1'b0;

        if (bram_dbus_ack) begin
            m_ack = 1'b1;
            m_rdata = bram_dbus_rdata;
        end else if (debugmmio_ack) begin
            m_ack = 1'b1;
            m_rdata = debugmmio_rdata;
        end else if (uart_console_ack) begin
            m_ack = 1'b1;
            m_rdata = uart_console_rdata;
        end else if (bram_dbus_err || debugmmio_err || uart_console_err) begin
            m_err = 1'b1;
        end
    end

    // Core response back to BIU.
    always_comb begin
        dbus_ack = 1'b0;
        dbus_err = 1'b0;
        dbus_rdata = 32'h0000_0000;

        if (source_core_q && m_ack) begin
            dbus_ack = 1'b1;
            dbus_rdata = m_rdata;
        end else if (source_core_q && (m_err || core_decode_err_q)) begin
            dbus_err = 1'b1;
        end
    end

    // Debug MMIO debug-master response.
    assign mmio_dbg_mem_done = source_mmio_dbg_q && (m_ack || mmio_dbg_decode_err_q || m_err);
    assign mmio_dbg_mem_rdata = m_rdata;
    assign mmio_dbg_mem_err = source_mmio_dbg_q && (m_err || mmio_dbg_decode_err_q);

    // UART debug-agent memory-master response.
    assign uart_dbg_mem_done = source_uart_dbg_q && (m_ack || uart_dbg_decode_err_q || m_err);
    assign uart_dbg_mem_rdata = m_rdata;
    assign uart_dbg_mem_err = source_uart_dbg_q && (m_err || uart_dbg_decode_err_q);

    logic unused_debug_active;
    assign unused_debug_active = uart_debug_active_eff ^ core_current_pc_i[0];
endmodule : mem
