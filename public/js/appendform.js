// script to append the first modal's field values to the form
$( document ).ready(function() {

  smoothScroll.init();
  
  $('button.demo-form-button').click(function(){
      $('form#demo-form').each(function(){
          $(this).submit();
      });
  });

  // $('#teacher-info').on('submit', function(event) {
  //   // event.preventDefault();
  //   var teacherinfo = $("#teacher-info").serializeArray();
  //   console.log(teacherinfo);


  //   for (var i = 0; i < teacherinfo.length; i++) {
  //     console.log(teacherinfo[i]);
  //     var input = $('<input>')
  //                   .attr('type', 'hidden')
  //                   .attr('name', teacherinfo[i]['name'])
  //                   .val(teacherinfo[i]['value']);
  //     $('#login').append($(input));
  //   }

  //   var role = $('<input>')
  //                 .attr('type', 'hidden')
  //                 .attr('name', 'role')
  //                 .val('teacher');
  //   $('#login').append($(role));

  //   console.log($(this).serializeArray());

  // });


  $('#login').on('submit', function(event) {
    // event.preventDefault();
    var teacherinfo = $("#teacher-info").serializeArray();
    console.log(teacherinfo);


    for (var i = 0; i < teacherinfo.length; i++) {
      console.log(teacherinfo[i]);
      var input = $('<input>')
                    .attr('type', 'hidden')
                    .attr('name', teacherinfo[i]['name'])
                    .val(teacherinfo[i]['value']);
      $('#login').append($(input));
    }

    var role = $('<input>')
                  .attr('type', 'hidden')
                  .attr('name', 'role')
                  .val('teacher');
    $('#login').append($(role));

    console.log($(this).serializeArray());

  });


  $('#admin-login').submit(function(event) {

    var adminInfo = $('#teacher-info').serializeArray();
    console.log(adminInfo);

    for (var i = 0; i < adminInfo.length; i++) {
      console.log(adminInfo[i])
      var input = $('<input>')
                    .attr('type', 'hidden')
                    .attr('name', adminInfo[i]['name']).val(adminInfo[i]['value']);
      $('#admin-login').append($(input));
    }

    var first_name = $("#admin-login").find("input[name=first_name]").val();
    var last_name = $("#admin-login").find("input[name=last_name]").val();
    var signature = first_name + " " + last_name;
    console.log('signature : ' + signature);
    var input = $('<input>')
                    .attr('type', 'hidden')
                    .attr('name', 'signature')
                    .val(signature);
    $('#admin-login').append($(input));

    var role = $('<input>')
                  .attr('type', 'hidden')
                  .attr('name', 'role')
                  .val('admin');
    $('#admin-login').append($(role));

  });

});



