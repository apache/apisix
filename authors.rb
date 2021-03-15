# ruby authors.rb
authors=`git shortlog -sne --pretty="%n" | sort -r | uniq`
contributors=authors.split("\n")
  .map{|x| [x.split.first.to_i, x.split(' ')[1..-2], x.split.last]}
  .group_by{|x| x[2]}
  .map{|k, v| [v.inject(0){|s, a| s + a[0]}, v.inject(''){|s ,a| a[1].join(' ')}, k]}
  .sort_by{|x, y, z| -x}.map{|x| x.join(' ')}.join("\n")
File.open('AUTHORS.md', 'w'){|file| file.write("#{contributors}\n")}
