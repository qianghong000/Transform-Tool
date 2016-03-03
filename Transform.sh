#!/bin/bash
TIME=`date +%Y%m%d`
LOG=transform_${TIME}.log
echo "Start execute sql statement at `date`." >>${LOG}  
HOSTNAME="192.168.7.146"
PORT="3306"
USERNAME="root"
PASSWORD="123.com"
DBNAME="jgwf"
TABLENAME="jgwf_ware"
SPATH="/opt/transform/Ware/untransform"
#查询数据库状态
CYCLING(){
n=5   #每次查询数据库条数
z=0   #扫描阈值
for((x=0;;))
  do
  #从上次扫描结束id位置开始，每次取n条数据
  select_id_sql="select w_id from $DBNAME.$TABLENAME where w_status IN(0,2) and w_id>$x limit $n"
  res=$(mysql -u $USERNAME -p$PASSWORD -s -N -e "
  $select_id_sql;
  quit")
   echo $res
  #获取查询到的最后一个id,给变量重新赋值
  x=` echo $res |awk '{print $NF}' `
  #如果查询结果非空则继续
  if [ ! -z "$res" ];then
     for i in $res;
     do
        #如果为数字则继续
        if [ -n "$(echo $i| sed -n "/^[0-9]\+$/p")" ];then
	   DIR=`find $SPATH/ -mindepth 2 -type d  -name $i`
	   cd $DIR
	  #设置目标路径
	   DPATH=$(pwd |sed 's/untransform/transform/g')
	   Catch_date
	else
  #         mysql -u $USERNAME -p$PASSWORD -s -N -e "
  #         $update_FALSE_sql;
  #         quit"
	   echo "w_id:$i is not number!" 
	fi
     done
  else
  #如果下次查询结果为空跳出循环
	echo "All Done." &&exit 0
  fi
done
}

Catch_date(){
#查询数据库里是否存在需转码文件
# select_status_sql="select w_status from $DBNAME.$TABLENAME where w_id=$i"
update_OK_sql="update $DBNAME.$TABLENAME set w_status=1 where w_id=$i"    #1/成功
update_NO_sql="update $DBNAME.$TABLENAME set w_status=2 where w_id=$i"     #2/部分失败
update_FALSE_sql="update $DBNAME.$TABLENAME set w_status=3 where w_id=$i"     #3/失败,意外终止
select_all_sql="select w_video,w_word,w_ppt from $DBNAME.$TABLENAME where w_id=$i"
cat_sql=$(mysql -u $USERNAME -p$PASSWORD -s -N -e "
$select_all_sql;
quit")
#去除字符串中的空格
res_all=$(echo ${cat_sql} |sed s/[[:space:]]//g)
echo $res_all
#数据库中存在,则创建文件夹并进行解码
if [ -n "${res_all}" ];then
   echo $DPATH
   mkdir -p $DPATH
   for filename in ${cat_sql} ; do
        echo $filename
        Transform
  done
else
echo "Warning: $DPATH is not file need to transform!"
#     mysql -u $USERNAME -p$PASSWORD -s -N -e "
#     $update_FALSE_sql;
#     quit"&& echo "Warning: $DPATH is not file need to transform!"
     continue
fi
}

Transform(){
  #所有操作状态标示
  status='True'
  #去除后缀，提取文件名
  name=${filename%.*}
  #去除后缀，进行文件名拼接
  ppt_name=${name}'_p'
  #判断文件后缀
  if [ ${filename##*.} == "docx" ] ; then
  #使用openffice将DOCX文档转换为PDF格式
	/usr/bin/python /opt/openoffice4/program/DocumentConvert.py $DIR/$filename $DPATH/$name.pdf
	if [ $(echo $?) == 0 ];then
	    #使用pdf2swf将PDF文档转换为SWF格式
		 file_dir=$DPATH/$name.swf
		 pdf2swf -o $file_dir -T -z -t $DPATH/$name.pdf -s languagedir=/usr/share/xpdf/xpdf-chinese-simplified -s flashversion=9
	         Alter
	else
		#如果第一次转换失败，修改所有操作状态标示，并记录状态值为3
		status='False'
		mysql -u $USERNAME -p$PASSWORD -s -N -e "
			$update_FALSE_sql;
			quit"&& echo "ERROR: $DIR$filename is not transformed!"
	fi
  #	mv $SPATH/$filename $DPATH/$filename && echo "Filename: $DPATH/$filename"
  elif [ ${filename##*.} == "pptx" ] || [ -f $filename  -a  ${filename##*.} == "ppt" ]; then 
  /usr/bin/python /opt/openoffice4/program/DocumentConvert.py $DIR/$filename $DPATH/$ppt_name.pdf
	if [ $(echo $?) == 0 ];then	
	     #使用pdf2swf将PDF文档转换为SWF格式
	     file_dir=$DPATH/$ppt_name.swf
	     pdf2swf -o $file_dir -T -z -t $DPATH/$ppt_name.pdf -s languagedir=/usr/share/xpdf/xpdf-chinese-simplified -s flashversion=9 -s poly2bitmap
	     Alter
	else
	     status='False'
	     mysql -u $USERNAME -p$PASSWORD -s -N -e "
	     $update_NO_sql;
	     quit"&& echo "ERROR: $DIR$filename is not transformed!"
        fi
  elif [ ${filename##*.} == "pdf" ] ; then  
	file_dir=$DPATH/$name.swf
	pdf2swf -o $file_dir -T -z -t $DIR/$filename -s languagedir=/usr/share/xpdf/xpdf-chinese-simplified -s flashversion=9 -s poly2bitmap
	Alter
  elif [ ${filename##*.} == "FLV" ] || [ ${filename##*.} == "flv" ] ; then
	file_dir=$DPATH/$name.mp4
	ffmpeg -y -i $DIR/$filename -vcodec h264 $file_dir && ffmpeg -i $file_dir -y -r 1 -ss 1 -t 0.001 -s 90x160 -f image2 $DPATH/$name.jpeg
	Alter
  elif [ ${filename##*.} == "AVI" ] || [ ${filename##*.} == "avi" ] ; then 
	file_dir=$DPATH/$name.mp4
	ffmpeg -i $DIR/$filename -y -f mp4 -vcodec mpeg4 -acodec aac -strict -2 -s 480x360 $file_dir && ffmpeg -i $file_dir -y -r 1 -ss 1 -t 0.001 -s 90x160 -f image2 $DPATH/$name.jpeg
#        ffmpeg -i $DIR/$filename -f psp -r 29.97 -b 768k -ar 24000 -ab 64k -s 640x480 $file_dir
	Alter
  elif [ ${filename##*.} == "MKV" ] || [ ${filename##*.} == "mkv" ]; then 
	file_dir=$DPATH/$name.mp4
	ffmpeg -i $DIR/$filename -y -vcodec copy -acodec copy $file_dir && ffmpeg -i $file_dir -y -r 1 -ss 1 -t 0.001 -s 90x160 -f image2 $DPATH/$name.jpeg
	Alter
  elif [ ${filename##*.} == "MOV" ] || [ ${filename##*.} == "MOV" ]; then
	file_dir=$DPATH/$name.mp4
	ffmpeg -i $DIR/$filename -vcodec libx264 -strict experimental $file_dir && ffmpeg -i $file_dir -y -r 1 -ss 1 -t 0.001 -s 90x160 -f image2 $DPATH/$name.jpeg
	Alter
  elif [ ${filename##*.} == "zip" ] ; then 
        continue
  #如果没有匹配到需转码文件则跳出
  else
	continue 
  fi 
}

#判断转码是否成功，成功则修改状态为1，失败修改为2
Alter(){
    ret=$(echo $?)
    if [ $ret == 0 ];then
        echo "OK: $file_dir is transform succeed!"
        #如果所有操作状态为真，则继续并修改状态码为1，否则不做状态码修改
	if [ $status='True' ];then
	    mysql -u $USERNAME -p$PASSWORD -s -N -e "
           $update_OK_sql;
           quit"
	else
	    continue
	fi
    #如果转码失败，修改所有操作状态为假
    else
	status='False'
	mysql -u $USERNAME -p$PASSWORD -s -N -e "
        $update_NO_sql;
        quit" &&echo "ERROR: $file_dir is not transformed!"
    fi
}

CYCLING
