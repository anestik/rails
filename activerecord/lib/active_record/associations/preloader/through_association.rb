# frozen_string_literal: true

module ActiveRecord
  module Associations
    class Preloader
      class ThroughAssociation < Association # :nodoc:
        PRELOADER = ActiveRecord::Associations::Preloader.new(associate_by_default: true)

        def initialize(*)
          super
          @already_loaded = owners.first.association(through_reflection.name).loaded?
        end

        def preloaded_records
          @preloaded_records ||= source_preloaders.flat_map(&:preloaded_records)
        end

        def records_by_owner
          return @records_by_owner if defined?(@records_by_owner)
          source_records_by_owner = source_preloaders.map(&:records_by_owner).reduce(:merge)
          through_records_by_owner = through_preloaders.map(&:records_by_owner).reduce(:merge)

          @records_by_owner = owners.each_with_object({}) do |owner, result|
            through_records = through_records_by_owner[owner] || []

            if @already_loaded
              if source_type = reflection.options[:source_type]
                through_records = through_records.select do |record|
                  record[reflection.foreign_type] == source_type
                end
              end
            end

            records = through_records.flat_map do |record|
              source_records_by_owner[record]
            end

            records.compact!
            records.sort_by! { |rhs| preload_index[rhs] } if scope.order_values.any?
            records.uniq! if scope.distinct_value
            result[owner] = records
          end
        end

        private
          def source_preloaders
            @source_preloaders ||= PRELOADER.preload(middle_records, source_reflection.name, scope)
          end

          def middle_records
            through_preloaders.flat_map(&:preloaded_records)
          end

          def through_preloaders
            @through_preloaders ||= PRELOADER.preload(owners, through_reflection.name, through_scope)
          end

          def through_reflection
            reflection.through_reflection
          end

          def source_reflection
            reflection.source_reflection
          end

          def preload_index
            @preload_index ||= preloaded_records.each_with_object({}).with_index do |(record, result), index|
              result[record] = index
            end
          end

          def through_scope
            scope = through_reflection.klass.unscoped
            options = reflection.options

            values = reflection_scope.values
            if annotations = values[:annotate]
              scope.annotate!(*annotations)
            end

            if options[:source_type]
              scope.where! reflection.foreign_type => options[:source_type]
            end

            scope
          end
      end
    end
  end
end
