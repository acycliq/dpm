
data_dir = '.';

config_glob=[data_dir '/*.config.txt' ];
fileList = glob(config_glob);

file = fileList{1,1};

config=load(file);

print_struct_array_contents(true);
disp(config);

dS = config.hyper;
dS = rmfield(dS, 'a');
dS = rmfield(dS, 'b');

printf("Display fields after removing a and b");
disp(dS);
