module VowpalWabbit
  class Model
    def initialize(**params)
      # add strict parse once exceptions are handled properly
      # https://github.com/VowpalWabbit/vowpal_wabbit/issues/2004
      @params = {quiet: true}.merge(params)
    end

    def fit(x, y = nil)
      @handle = nil
      partial_fit(x, y)
    end

    def partial_fit(x, y = nil)
      each_example(x, y) do |example|
        FFI.VW_Learn(handle, example)
      end
      nil
    end

    def predict(x)
      out = []
      each_example(x) do |example|
        out << predict_example(example)
      end
      out
    end

    def coefs
      num_weights = FFI.VW_Num_Weights(handle)
      coefs = {}
      num_weights.times.map do |i|
        weight = FFI.VW_Get_Weight(handle, i, 0)
        coefs[i] = weight if weight != 0
      end
      coefs
    end

    def save_model(filename)
      buffer_handle = ::FFI::MemoryPointer.new(:pointer)
      output_data = ::FFI::MemoryPointer.new(:pointer)
      output_size = ::FFI::MemoryPointer.new(:size_t)
      FFI.VW_CopyModelData(handle, buffer_handle, output_data, output_size)
      bin_str = output_data.read_pointer.read_string(output_size.read(:size_t))
      FFI.VW_FreeIOBuf(buffer_handle.read_pointer)
      File.binwrite(filename, bin_str)
      nil
    end

    def load_model(filename)
      bin_str = File.binread(filename)
      model_data = ::FFI::MemoryPointer.new(:char, bin_str.bytesize)
      model_data.put_bytes(0, bin_str)
      @handle = FFI.VW_InitializeWithModel(param_str, model_data, bin_str.bytesize)
      nil
    end

    private

    # TODO clean-up handle
    def handle
      @handle ||= FFI.VW_InitializeA(param_str)
    end

    def param_str
      args =
        @params.map do |k, v|
          check_param(k.to_s)
          check_param(v.to_s)

          if v == true
            "--#{k}"
          elsif !v
            nil
          elsif k.size == 1
            "-#{k} #{v}"
          else
            "--#{k} #{v}"
          end
        end
      args.compact.join(" ")
    end

    def check_param(v)
      raise ArgumentError, "Invalid parameter" if /[[:space:]]/.match(v)
    end

    def predict_example(example)
      if @params[:cb]
        FFI.VW_PredictCostSensitive(handle, example)
      else
        FFI.VW_Predict(handle, example)
      end
    end

    # get both in one pass for efficiency
    def predict_for_score(x, y)
      if x.is_a?(String) && !y
        y_pred = []
        y = []
        each_example(x) do |example|
          y_pred << predict_example(example)
          y << FFI.VW_GetLabel(example)
        end
        [y_pred, y]
      else
        [predict(x), y]
      end
    end

    # TODO support compressed files
    def each_example(x, y = nil)
      each_line(x, y) do |line|
        example = FFI.VW_ReadExampleA(handle, line)
        yield example
        FFI.VW_FinishExample(handle, example)
      end
    end

    def each_line(x, y)
      if x.is_a?(String)
        raise ArgumentError, "Cannot pass y with file" if y

        File.foreach(x) do |line|
          yield line
        end
      else
        raise ArgumentError, "x and y must have same size" if y && x.size != y.size

        x.zip(y || []) do |xi, yi|
          if xi.is_a?(String)
            yield xi
          else
            yield "#{yi} 1 | #{xi.map.with_index { |v, i| "#{i}:#{v}" }.join(" ")}"
          end
        end
      end
    end
  end
end