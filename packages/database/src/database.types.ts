export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      cash_movements: {
        Row: {
          adjusts_cash_session_id: string | null
          amount_gs: number
          cash_session_id: string
          created_at: string
          created_by_user_id: string
          id: string
          movement_type: string
          occurred_at: string
          reason: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          adjusts_cash_session_id?: string | null
          amount_gs: number
          cash_session_id: string
          created_at?: string
          created_by_user_id: string
          id?: string
          movement_type: string
          occurred_at: string
          reason: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          adjusts_cash_session_id?: string | null
          amount_gs?: number
          cash_session_id?: string
          created_at?: string
          created_by_user_id?: string
          id?: string
          movement_type?: string
          occurred_at?: string
          reason?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cash_movements_adjusts_cash_session_id_fkey"
            columns: ["adjusts_cash_session_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "cash_sessions"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "cash_movements_cash_session_id_fkey"
            columns: ["cash_session_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "cash_sessions"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "cash_movements_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      cash_sessions: {
        Row: {
          business_date: string
          cash_difference_gs: number | null
          closed_at: string | null
          closed_by_user_id: string | null
          closing_note: string | null
          counted_cash_gs: number | null
          created_at: string
          establishment_id: string
          expected_cash_gs: number | null
          id: string
          opened_at: string
          opened_by_user_id: string
          opening_float_gs: number
          pos_terminal_id: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          business_date: string
          cash_difference_gs?: number | null
          closed_at?: string | null
          closed_by_user_id?: string | null
          closing_note?: string | null
          counted_cash_gs?: number | null
          created_at?: string
          establishment_id: string
          expected_cash_gs?: number | null
          id?: string
          opened_at: string
          opened_by_user_id: string
          opening_float_gs?: number
          pos_terminal_id: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          business_date?: string
          cash_difference_gs?: number | null
          closed_at?: string | null
          closed_by_user_id?: string | null
          closing_note?: string | null
          counted_cash_gs?: number | null
          created_at?: string
          establishment_id?: string
          expected_cash_gs?: number | null
          id?: string
          opened_at?: string
          opened_by_user_id?: string
          opening_float_gs?: number
          pos_terminal_id?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cash_sessions_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "cash_sessions_pos_terminal_id_fkey"
            columns: ["pos_terminal_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "pos_terminals"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "cash_sessions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      customers: {
        Row: {
          created_at: string
          doc_number: string
          doc_type: string
          email: string | null
          id: string
          name: string
          phone: string | null
          ruc_dv: number | null
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          doc_number: string
          doc_type: string
          email?: string | null
          id?: string
          name: string
          phone?: string | null
          ruc_dv?: number | null
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          doc_number?: string
          doc_type?: string
          email?: string | null
          id?: string
          name?: string
          phone?: string | null
          ruc_dv?: number | null
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customers_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      dining_areas: {
        Row: {
          created_at: string
          display_order: number
          establishment_id: string
          id: string
          name: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          establishment_id: string
          id?: string
          name: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          establishment_id?: string
          id?: string
          name?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dining_areas_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "dining_areas_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      dining_tables: {
        Row: {
          code: string
          created_at: string
          dining_area_id: string
          establishment_id: string
          id: string
          position_x: number | null
          position_y: number | null
          seats: number | null
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          dining_area_id: string
          establishment_id: string
          id?: string
          position_x?: number | null
          position_y?: number | null
          seats?: number | null
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          dining_area_id?: string
          establishment_id?: string
          id?: string
          position_x?: number | null
          position_y?: number | null
          seats?: number | null
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dining_tables_area_id_fkey"
            columns: ["dining_area_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "dining_areas"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "dining_tables_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "dining_tables_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      document_cancellations: {
        Row: {
          created_at: string
          document_id: string
          id: string
          reason: string
          received_at: string
          requested_at: string
          requested_by_user_id: string
          response_code: string | null
          response_message: string | null
          sifen_status: string
          tenant_id: string
          transmit_attempts: number
          transmitted_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          document_id: string
          id?: string
          reason: string
          received_at?: string
          requested_at: string
          requested_by_user_id: string
          response_code?: string | null
          response_message?: string | null
          sifen_status?: string
          tenant_id: string
          transmit_attempts?: number
          transmitted_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          document_id?: string
          id?: string
          reason?: string
          received_at?: string
          requested_at?: string
          requested_by_user_id?: string
          response_code?: string | null
          response_message?: string | null
          sifen_status?: string
          tenant_id?: string
          transmit_attempts?: number
          transmitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_cancellations_document_id_fkey"
            columns: ["document_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_cancellations_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      document_counters: {
        Row: {
          created_at: string
          document_type: string
          establishment_id: string
          id: string
          last_number: number
          pos_terminal_id: string
          range_from: number
          range_to: number
          status: string
          tenant_id: string
          timbrado_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          document_type: string
          establishment_id: string
          id?: string
          last_number?: number
          pos_terminal_id: string
          range_from: number
          range_to: number
          status?: string
          tenant_id: string
          timbrado_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          document_type?: string
          establishment_id?: string
          id?: string
          last_number?: number
          pos_terminal_id?: string
          range_from?: number
          range_to?: number
          status?: string
          tenant_id?: string
          timbrado_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_counters_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_counters_pos_terminal_id_fkey"
            columns: ["pos_terminal_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "pos_terminals"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "document_counters_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_counters_timbrado_id_fkey"
            columns: ["timbrado_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "fiscal_timbrados"
            referencedColumns: ["id", "tenant_id"]
          },
        ]
      }
      document_line_modifiers: {
        Row: {
          created_at: string
          display_order: number
          document_line_id: string
          id: string
          modifier_group_name: string
          modifier_option_id: string
          name: string
          price_delta_gs: number
          sequence_number: number
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          document_line_id: string
          id?: string
          modifier_group_name: string
          modifier_option_id: string
          name: string
          price_delta_gs: number
          sequence_number: number
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          document_line_id?: string
          id?: string
          modifier_group_name?: string
          modifier_option_id?: string
          name?: string
          price_delta_gs?: number
          sequence_number?: number
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_line_modifiers_document_line_id_fkey"
            columns: ["document_line_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "document_lines"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_line_modifiers_modifier_option_id_fkey"
            columns: ["modifier_option_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "modifier_options"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_line_modifiers_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      document_lines: {
        Row: {
          created_at: string
          discount_gs: number
          document_id: string
          document_type: string
          id: string
          iva_amount_gs: number
          iva_rate: number
          line_number: number
          line_total_gs: number
          modifiers_total_gs: number
          order_line_id: string | null
          product_category_name: string
          product_id: string
          product_name: string
          quantity: number
          taxable_base_gs: number
          tenant_id: string
          unit_price_gs: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          discount_gs?: number
          document_id: string
          document_type: string
          id?: string
          iva_amount_gs: number
          iva_rate: number
          line_number: number
          line_total_gs: number
          modifiers_total_gs?: number
          order_line_id?: string | null
          product_category_name: string
          product_id: string
          product_name: string
          quantity: number
          taxable_base_gs: number
          tenant_id: string
          unit_price_gs: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          discount_gs?: number
          document_id?: string
          document_type?: string
          id?: string
          iva_amount_gs?: number
          iva_rate?: number
          line_number?: number
          line_total_gs?: number
          modifiers_total_gs?: number
          order_line_id?: string | null
          product_category_name?: string
          product_id?: string
          product_name?: string
          quantity?: number
          taxable_base_gs?: number
          tenant_id?: string
          unit_price_gs?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_lines_document_id_fkey"
            columns: ["document_id", "tenant_id", "document_type"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id", "tenant_id", "document_type"]
          },
          {
            foreignKeyName: "document_lines_order_line_id_fkey"
            columns: ["order_line_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_lines_product_id_fkey"
            columns: ["product_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_lines_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      document_transmission_events: {
        Row: {
          attempt_number: number
          created_at: string
          document_cancellation_id: string | null
          document_id: string | null
          id: string
          outcome: string
          request_payload_hash: string | null
          response_code: string | null
          response_message: string | null
          status: string
          tenant_id: string
          transmitted_at: string
          updated_at: string
        }
        Insert: {
          attempt_number: number
          created_at?: string
          document_cancellation_id?: string | null
          document_id?: string | null
          id?: string
          outcome: string
          request_payload_hash?: string | null
          response_code?: string | null
          response_message?: string | null
          status?: string
          tenant_id: string
          transmitted_at: string
          updated_at?: string
        }
        Update: {
          attempt_number?: number
          created_at?: string
          document_cancellation_id?: string | null
          document_id?: string | null
          id?: string
          outcome?: string
          request_payload_hash?: string | null
          response_code?: string | null
          response_message?: string | null
          status?: string
          tenant_id?: string
          transmitted_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_transmission_events_cancellation_id_fkey"
            columns: ["document_cancellation_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "document_cancellations"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_transmission_events_document_id_fkey"
            columns: ["document_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "document_transmission_events_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      documents: {
        Row: {
          anonymous_buyer_threshold_gs: number
          anonymous_threshold_from: string
          authorized_range_from: number
          authorized_range_to: number
          business_date: string
          buyer_doc_number: string | null
          buyer_doc_type: string | null
          buyer_name: string | null
          buyer_ruc_dv: number | null
          cash_session_id: string
          cdc: string | null
          certificate_expires_at: string
          created_at: string
          credit_note_scope: string | null
          customer_id: string | null
          discount_total_gs: number
          document_type: string
          establishment_code: string
          establishment_id: string
          expedition_point_code: string
          id: string
          issuer_legal_name: string
          issuer_ruc: string
          issuer_ruc_dv: number
          iva_10_gs: number
          iva_5_gs: number
          line_count: number
          number: number
          order_id: string | null
          pos_terminal_id: string
          received_at: string
          references_document_id: string | null
          references_document_type: string | null
          sifen_response_code: string | null
          sifen_response_message: string | null
          sifen_status: string
          signed_at: string
          signing_certificate_id: string
          status: string
          taxable_base_10_gs: number
          taxable_base_5_gs: number
          tenant_id: string
          timbrado_id: string
          timbrado_number: string
          timbrado_valid_from: string
          timbrado_valid_to: string | null
          total_gs: number
          transmit_attempts: number
          transmit_deadline_at: string
          transmitted_at: string | null
          updated_at: string
        }
        Insert: {
          anonymous_buyer_threshold_gs: number
          anonymous_threshold_from: string
          authorized_range_from: number
          authorized_range_to: number
          business_date: string
          buyer_doc_number?: string | null
          buyer_doc_type?: string | null
          buyer_name?: string | null
          buyer_ruc_dv?: number | null
          cash_session_id: string
          cdc?: string | null
          certificate_expires_at: string
          created_at?: string
          credit_note_scope?: string | null
          customer_id?: string | null
          discount_total_gs?: number
          document_type: string
          establishment_code: string
          establishment_id: string
          expedition_point_code: string
          id?: string
          issuer_legal_name: string
          issuer_ruc: string
          issuer_ruc_dv: number
          iva_10_gs?: number
          iva_5_gs?: number
          line_count: number
          number: number
          order_id?: string | null
          pos_terminal_id: string
          received_at?: string
          references_document_id?: string | null
          references_document_type?: string | null
          sifen_response_code?: string | null
          sifen_response_message?: string | null
          sifen_status?: string
          signed_at: string
          signing_certificate_id: string
          status?: string
          taxable_base_10_gs?: number
          taxable_base_5_gs?: number
          tenant_id: string
          timbrado_id: string
          timbrado_number: string
          timbrado_valid_from: string
          timbrado_valid_to?: string | null
          total_gs: number
          transmit_attempts?: number
          transmit_deadline_at: string
          transmitted_at?: string | null
          updated_at?: string
        }
        Update: {
          anonymous_buyer_threshold_gs?: number
          anonymous_threshold_from?: string
          authorized_range_from?: number
          authorized_range_to?: number
          business_date?: string
          buyer_doc_number?: string | null
          buyer_doc_type?: string | null
          buyer_name?: string | null
          buyer_ruc_dv?: number | null
          cash_session_id?: string
          cdc?: string | null
          certificate_expires_at?: string
          created_at?: string
          credit_note_scope?: string | null
          customer_id?: string | null
          discount_total_gs?: number
          document_type?: string
          establishment_code?: string
          establishment_id?: string
          expedition_point_code?: string
          id?: string
          issuer_legal_name?: string
          issuer_ruc?: string
          issuer_ruc_dv?: number
          iva_10_gs?: number
          iva_5_gs?: number
          line_count?: number
          number?: number
          order_id?: string | null
          pos_terminal_id?: string
          received_at?: string
          references_document_id?: string | null
          references_document_type?: string | null
          sifen_response_code?: string | null
          sifen_response_message?: string | null
          sifen_status?: string
          signed_at?: string
          signing_certificate_id?: string
          status?: string
          taxable_base_10_gs?: number
          taxable_base_5_gs?: number
          tenant_id?: string
          timbrado_id?: string
          timbrado_number?: string
          timbrado_valid_from?: string
          timbrado_valid_to?: string | null
          total_gs?: number
          transmit_attempts?: number
          transmit_deadline_at?: string
          transmitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "documents_cash_session_id_fkey"
            columns: ["cash_session_id", "pos_terminal_id"]
            isOneToOne: false
            referencedRelation: "cash_sessions"
            referencedColumns: ["id", "pos_terminal_id"]
          },
          {
            foreignKeyName: "documents_certificate_id_fkey"
            columns: ["signing_certificate_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "fiscal_certificates"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "documents_customer_id_fkey"
            columns: ["customer_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "documents_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "documents_order_id_fkey"
            columns: ["order_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "documents_pos_terminal_id_fkey"
            columns: ["pos_terminal_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "pos_terminals"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "documents_references_document_id_fkey"
            columns: [
              "references_document_id",
              "tenant_id",
              "references_document_type",
            ]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id", "tenant_id", "document_type"]
          },
          {
            foreignKeyName: "documents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documents_timbrado_id_fkey"
            columns: ["timbrado_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "fiscal_timbrados"
            referencedColumns: ["id", "tenant_id"]
          },
        ]
      }
      establishments: {
        Row: {
          created_at: string
          establishment_code: string | null
          id: string
          name: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          establishment_code?: string | null
          id?: string
          name: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          establishment_code?: string | null
          id?: string
          name?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "establishments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      fiscal_certificates: {
        Row: {
          created_at: string
          establishment_id: string | null
          expires_at: string
          id: string
          issuer: string
          not_before: string
          serial_number: string
          status: string
          subject_ruc: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          establishment_id?: string | null
          expires_at: string
          id?: string
          issuer: string
          not_before: string
          serial_number: string
          status?: string
          subject_ruc: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          establishment_id?: string | null
          expires_at?: string
          id?: string
          issuer?: string
          not_before?: string
          serial_number?: string
          status?: string
          subject_ruc?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_certificates_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "fiscal_certificates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      fiscal_thresholds: {
        Row: {
          anonymous_buyer_threshold_gs: number
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          source_note: string | null
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          anonymous_buyer_threshold_gs: number
          created_at?: string
          effective_from: string
          effective_to?: string | null
          id?: string
          source_note?: string | null
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          anonymous_buyer_threshold_gs?: number
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          source_note?: string | null
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_thresholds_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      fiscal_timbrados: {
        Row: {
          created_at: string
          id: string
          number: string
          status: string
          tenant_id: string
          updated_at: string
          valid_from: string
          valid_to: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          number: string
          status?: string
          tenant_id: string
          updated_at?: string
          valid_from: string
          valid_to?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          number?: string
          status?: string
          tenant_id?: string
          updated_at?: string
          valid_from?: string
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_timbrados_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      modifier_groups: {
        Row: {
          created_at: string
          display_order: number
          id: string
          name: string
          selection_max: number
          selection_min: number
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          name: string
          selection_max?: number
          selection_min?: number
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          name?: string
          selection_max?: number
          selection_min?: number
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "modifier_groups_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      modifier_options: {
        Row: {
          created_at: string
          display_order: number
          id: string
          is_default: boolean
          modifier_group_id: string
          name: string
          price_delta_gs: number
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          is_default?: boolean
          modifier_group_id: string
          name: string
          price_delta_gs?: number
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          is_default?: boolean
          modifier_group_id?: string
          name?: string
          price_delta_gs?: number
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "modifier_options_group_id_fkey"
            columns: ["modifier_group_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "modifier_groups"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "modifier_options_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      order_line_modifiers: {
        Row: {
          created_at: string
          display_order: number
          id: string
          modifier_group_name: string
          modifier_option_id: string
          name: string
          order_line_id: string
          price_delta_gs: number
          sequence_number: number
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          modifier_group_name: string
          modifier_option_id: string
          name: string
          order_line_id: string
          price_delta_gs: number
          sequence_number: number
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          modifier_group_name?: string
          modifier_option_id?: string
          name?: string
          order_line_id?: string
          price_delta_gs?: number
          sequence_number?: number
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "order_line_modifiers_modifier_option_id_fkey"
            columns: ["modifier_option_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "modifier_options"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "order_line_modifiers_order_line_id_fkey"
            columns: ["order_line_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "order_line_modifiers_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      order_lines: {
        Row: {
          course: number | null
          created_at: string
          discount_gs: number
          id: string
          iva_rate: number
          kitchen_note: string | null
          line_number: number
          line_total_gs: number
          modifiers_total_gs: number
          order_id: string
          product_id: string
          product_name: string
          quantity: number
          seat_number: number | null
          sent_to_kitchen_at: string | null
          status: string
          tenant_id: string
          unit_price_gs: number
          updated_at: string
          void_reason: string | null
          voided_at: string | null
          voided_by_user_id: string | null
        }
        Insert: {
          course?: number | null
          created_at?: string
          discount_gs?: number
          id?: string
          iva_rate: number
          kitchen_note?: string | null
          line_number: number
          line_total_gs: number
          modifiers_total_gs?: number
          order_id: string
          product_id: string
          product_name: string
          quantity: number
          seat_number?: number | null
          sent_to_kitchen_at?: string | null
          status?: string
          tenant_id: string
          unit_price_gs: number
          updated_at?: string
          void_reason?: string | null
          voided_at?: string | null
          voided_by_user_id?: string | null
        }
        Update: {
          course?: number | null
          created_at?: string
          discount_gs?: number
          id?: string
          iva_rate?: number
          kitchen_note?: string | null
          line_number?: number
          line_total_gs?: number
          modifiers_total_gs?: number
          order_id?: string
          product_id?: string
          product_name?: string
          quantity?: number
          seat_number?: number | null
          sent_to_kitchen_at?: string | null
          status?: string
          tenant_id?: string
          unit_price_gs?: number
          updated_at?: string
          void_reason?: string | null
          voided_at?: string | null
          voided_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_lines_order_id_fkey"
            columns: ["order_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "order_lines_product_id_fkey"
            columns: ["product_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "order_lines_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      orders: {
        Row: {
          business_date: string
          cancel_reason: string | null
          channel: string
          closed_at: string | null
          closed_by_user_id: string | null
          code: string
          created_at: string
          establishment_id: string
          guest_count: number | null
          id: string
          note: string | null
          opened_at: string
          opened_by_user_id: string
          status: string
          table_id: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          business_date: string
          cancel_reason?: string | null
          channel: string
          closed_at?: string | null
          closed_by_user_id?: string | null
          code: string
          created_at?: string
          establishment_id: string
          guest_count?: number | null
          id?: string
          note?: string | null
          opened_at: string
          opened_by_user_id: string
          status?: string
          table_id?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          business_date?: string
          cancel_reason?: string | null
          channel?: string
          closed_at?: string | null
          closed_by_user_id?: string | null
          code?: string
          created_at?: string
          establishment_id?: string
          guest_count?: number | null
          id?: string
          note?: string | null
          opened_at?: string
          opened_by_user_id?: string
          status?: string
          table_id?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "orders_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "orders_table_id_fkey"
            columns: ["table_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "dining_tables"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "orders_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_reversals: {
        Row: {
          cash_session_id: string
          created_at: string
          id: string
          payment_id: string
          reason: string
          reversed_at: string
          reversed_by_user_id: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          cash_session_id: string
          created_at?: string
          id?: string
          payment_id: string
          reason: string
          reversed_at: string
          reversed_by_user_id: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          cash_session_id?: string
          created_at?: string
          id?: string
          payment_id?: string
          reason?: string
          reversed_at?: string
          reversed_by_user_id?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_reversals_cash_session_id_fkey"
            columns: ["cash_session_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "cash_sessions"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "payment_reversals_payment_id_fkey"
            columns: ["payment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "payment_reversals_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          amount_gs: number
          business_date: string
          cash_session_id: string
          change_gs: number
          charged_total_gs: number | null
          created_at: string
          created_by_user_id: string
          document_id: string | null
          establishment_id: string
          external_confirmed_at: string | null
          external_reference: string | null
          id: string
          method: string
          occurred_at: string
          order_id: string
          pos_terminal_id: string
          status: string
          tenant_id: string
          tendered_gs: number | null
          tip_gs: number
          updated_at: string
        }
        Insert: {
          amount_gs: number
          business_date: string
          cash_session_id: string
          change_gs?: number
          charged_total_gs?: number | null
          created_at?: string
          created_by_user_id: string
          document_id?: string | null
          establishment_id: string
          external_confirmed_at?: string | null
          external_reference?: string | null
          id?: string
          method: string
          occurred_at: string
          order_id: string
          pos_terminal_id: string
          status?: string
          tenant_id: string
          tendered_gs?: number | null
          tip_gs?: number
          updated_at?: string
        }
        Update: {
          amount_gs?: number
          business_date?: string
          cash_session_id?: string
          change_gs?: number
          charged_total_gs?: number | null
          created_at?: string
          created_by_user_id?: string
          document_id?: string | null
          establishment_id?: string
          external_confirmed_at?: string | null
          external_reference?: string | null
          id?: string
          method?: string
          occurred_at?: string
          order_id?: string
          pos_terminal_id?: string
          status?: string
          tenant_id?: string
          tendered_gs?: number | null
          tip_gs?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_cash_session_id_fkey"
            columns: ["cash_session_id", "pos_terminal_id"]
            isOneToOne: false
            referencedRelation: "cash_sessions"
            referencedColumns: ["id", "pos_terminal_id"]
          },
          {
            foreignKeyName: "payments_document_id_fkey"
            columns: ["document_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "payments_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "payments_order_id_fkey"
            columns: ["order_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "payments_pos_terminal_id_fkey"
            columns: ["pos_terminal_id", "establishment_id"]
            isOneToOne: false
            referencedRelation: "pos_terminals"
            referencedColumns: ["id", "establishment_id"]
          },
          {
            foreignKeyName: "payments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      pos_terminals: {
        Row: {
          created_at: string
          device_label: string | null
          establishment_id: string
          expedition_point_code: string
          id: string
          name: string
          order_code_prefix: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          device_label?: string | null
          establishment_id: string
          expedition_point_code: string
          id?: string
          name: string
          order_code_prefix: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          device_label?: string | null
          establishment_id?: string
          expedition_point_code?: string
          id?: string
          name?: string
          order_code_prefix?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pos_terminals_establishment_id_fkey"
            columns: ["establishment_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "establishments"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "pos_terminals_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      product_categories: {
        Row: {
          color: string | null
          created_at: string
          display_order: number
          id: string
          name: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          display_order?: number
          id?: string
          name: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          display_order?: number
          id?: string
          name?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_categories_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      product_modifier_groups: {
        Row: {
          created_at: string
          display_order: number
          id: string
          is_required: boolean
          modifier_group_id: string
          product_id: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          is_required?: boolean
          modifier_group_id: string
          product_id: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          is_required?: boolean
          modifier_group_id?: string
          product_id?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_modifier_groups_group_id_fkey"
            columns: ["modifier_group_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "modifier_groups"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "product_modifier_groups_product_id_fkey"
            columns: ["product_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "product_modifier_groups_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          category_id: string
          code: string | null
          created_at: string
          display_order: number
          id: string
          is_available: boolean
          iva_rate: number
          name: string
          price_gs: number
          short_name: string | null
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          category_id: string
          code?: string | null
          created_at?: string
          display_order?: number
          id?: string
          is_available?: boolean
          iva_rate?: number
          name: string
          price_gs: number
          short_name?: string | null
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          category_id?: string
          code?: string | null
          created_at?: string
          display_order?: number
          id?: string
          is_available?: boolean
          iva_rate?: number
          name?: string
          price_gs?: number
          short_name?: string | null
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "products_category_id_fkey"
            columns: ["category_id", "tenant_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id", "tenant_id"]
          },
          {
            foreignKeyName: "products_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_memberships: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["tenant_role"]
          status: string
          tenant_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["tenant_role"]
          status?: string
          tenant_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["tenant_role"]
          status?: string
          tenant_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_memberships_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          created_at: string
          id: string
          legal_name: string | null
          name: string
          ruc: string | null
          ruc_dv: number | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          legal_name?: string | null
          name: string
          ruc?: string | null
          ruc_dv?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          legal_name?: string | null
          name?: string
          ruc?: string | null
          ruc_dv?: number | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      assign_number_range: {
        Args: {
          p_document_type: string
          p_pos_terminal_id: string
          p_range_from: number
          p_range_to: number
          p_timbrado_id: string
        }
        Returns: string
      }
      bootstrap_tenant: {
        Args: { p_establishment_name: string; p_tenant_name: string }
        Returns: {
          establishment_id: string
          tenant_id: string
        }[]
      }
      cancel_document: {
        Args: {
          p_cancellation_id: string
          p_document_id: string
          p_reason: string
          p_requested_at: string
        }
        Returns: string
      }
      close_cash_session: {
        Args: {
          p_cash_session_id: string
          p_closed_at: string
          p_closing_note: string
          p_counted_cash_gs: number
        }
        Returns: {
          closing_counted_gs: number
          closing_difference_gs: number
          closing_expected_gs: number
        }[]
      }
      close_order: {
        Args: {
          p_cancel_reason: string
          p_closed_at: string
          p_order_id: string
        }
        Returns: string
      }
      issue_document: {
        Args: {
          p_business_date: string
          p_buyer_doc_number: string
          p_buyer_doc_type: string
          p_buyer_name: string
          p_buyer_ruc_dv: number
          p_cash_session_id: string
          p_customer_id: string
          p_document_id: string
          p_number: number
          p_order_id: string
          p_order_line_ids: string[]
          p_signed_at: string
        }
        Returns: {
          issued_document_id: string
          issued_number: number
          issued_total_gs: number
          was_created: boolean
        }[]
      }
      open_cash_session: {
        Args: {
          p_business_date: string
          p_cash_session_id: string
          p_expedition_point_id: string
          p_opened_at: string
          p_opening_float_gs: number
        }
        Returns: string
      }
      open_order: {
        Args: {
          p_business_date: string
          p_cash_session_id: string
          p_code: string
          p_dining_table_id: string
          p_guest_count: number
          p_note: string
          p_opened_at: string
          p_order_id: string
        }
        Returns: string
      }
      record_transmission_result: {
        Args: {
          p_cancellation_id: string
          p_cdc: string
          p_document_id: string
          p_outcome: string
          p_request_payload_hash: string
          p_response_code: string
          p_response_message: string
          p_transmitted_at: string
        }
        Returns: string
      }
      register_payment: {
        Args: {
          p_amount_gs: number
          p_business_date: string
          p_cash_session_id: string
          p_change_gs: number
          p_external_reference: string
          p_method: string
          p_occurred_at: string
          p_order_id: string
          p_payment_id: string
          p_tendered_gs: number
          p_tip_gs: number
        }
        Returns: string
      }
      set_fiscal_threshold: {
        Args: {
          p_amount_gs: number
          p_effective_from: string
          p_establishment_id: string
        }
        Returns: string
      }
    }
    Enums: {
      tenant_role: "owner" | "admin" | "member"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      tenant_role: ["owner", "admin", "member"],
    },
  },
} as const

