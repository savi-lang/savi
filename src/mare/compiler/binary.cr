require "file"
require "llvm"

class Mare::Compiler::Binary
  getter! exitcode : Int32
  
  PONYRT_BC_PATH = "/usr/local/lib/libponyrt.bc"
  
  def self.run(ctx)
    new.run(ctx)
  end
  
  def run(ctx)
    llvm = ctx.code_gen.llvm
    machine = ctx.code_gen.target_machine
    mod = ctx.code_gen.mod
    
    ponyrt_bc = LLVM::MemoryBuffer.from_file(PONYRT_BC_PATH)
    ponyrt = llvm.parse_bitcode(ponyrt_bc).as(LLVM::Module)
    
    # Link the pony runtime bitcode into the generated module.
    LibLLVM.link_modules(mod.to_unsafe, ponyrt.to_unsafe)
    
    bin_filename = File.tempname(".mare.user.program")
    obj_filename = "#{bin_filename}.o"
    
    machine.emit_obj_to_file(mod, obj_filename)
    
    link_args = %w{clang
      -fuse-ld=lld -rdynamic -static -fpic
      -lc -pthread -ldl -latomic -lexecinfo
    }
    link_args << obj_filename
    link_args << "-o" << "main" # TODO: customizable output binary filename
    
    res =  Process.run("/usr/bin/env", link_args, output: STDOUT, error: STDERR)
    raise "linker failed" unless res.exit_status == 0
  # ensure
  #   File.delete(obj_filename) if obj_filename
  end
end
