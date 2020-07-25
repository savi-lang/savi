require "../../dsl_spec"

class SubCommandWhenDuplicateAliasNameCase1 < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command" do
      alias_name "sub_command" # duplicate
      run do |opts, args|
      end
    end
  end
end

describe "Call the command." do
  it "raises an Exception when duplicate command name (case1)." do
    expect_raises(Exception, "There are duplicate registered commands. [sub_command]") do
      SubCommandWhenDuplicateAliasNameCase1.start_parse([] of String)
    end
  end
end

class SubCommandWhenDuplicateAliasNameCase2 < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command1" do
      alias_name "sub_command1", "sub_command2", "sub_command2" # duplicate "sub_command1" and "sub_command2"
      run do |opts, args|
      end
    end
  end
end

describe "Call the command." do
  it "raises an Exception when duplicate command name (case2)." do
    expect_raises(Exception, "There are duplicate registered commands. [sub_command1,sub_command2]") do
      SubCommandWhenDuplicateAliasNameCase2.start_parse([] of String)
    end
  end
end

class SubCommandWhenDuplicateAliasNameCase3 < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command1" do
      alias_name "alias_name1"
      run do |opts, args|
      end
    end
    sub "sub_command2" do
      alias_name "alias_name2"
      run do |opts, args|
      end
    end
    sub "sub_command3" do
      alias_name "sub_command1", "sub_command2", "alias_name1", "alias_name2"
      run do |opts, args|
      end
    end
  end
end

describe "Call the command." do
  it "raises an Exception when duplicate command name (case3)." do
    expect_raises(Exception, "There are duplicate registered commands. [sub_command1,sub_command2,alias_name1,alias_name2]") do
      SubCommandWhenDuplicateAliasNameCase3.start_parse([] of String)
    end
  end
end
