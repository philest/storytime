$(document).ready(function () {
  // THIS IS WHERE I'LL DO THE SIGNUP FLOW
  // 
  // 
  $('#signup-email-button').click(function(event) {
    console.log('opening signup-name-password....');
    event.preventDefault();

    $('#signup-email').validate({ // initialize the plugin
        rules: {
            email: {
                required: true,
                // email: true
            }
        }
    }).form();

    var ValidStatus = $("#signup-email").valid();
    if (ValidStatus == false) {
        return false;
    }

    $('#signupNamePassword').modal('toggle');
  });

  $('#signup-name-password-button').click(function(event) {
    console.log('opening signup school role....');
    event.preventDefault();
    $('#signup-name-password').validate({ // initialize the plugin
        rules: {
            first_name: {
                required: true
            },
            last_name: {
              required: true
            },
            password: {
                required: true
            }
        }
    }).form();

    var ValidStatus = $("#signup-name-password").valid();
    console.log(ValidStatus);
    if (ValidStatus == false) {
        return false;
    }

    // we want to POST this, clear the first-signup-form, the move on to the next modal
    $('#signup-name-password').submit();

    // move on to next modal
    $('#signupSchoolRole').modal('toggle');
  });

  $('#signup-school-role-button').click(function(event) {
    $('#signupSignature').modal('toggle');
  });

  $('#signup-signature-button').click(function(event) {
    event.preventDefault();
    $('#signup-signature').validate({ // initialize the plugin
        rules: {
            signature: {
                required: true
            }
        }
    }).form();

    var ValidStatus = $("#signup-signature").valid();
    if (ValidStatus == false) {
        return false;
    }
    $('#schoolInfo').modal('toggle');
  });

  $('#school-info-button').click(function(event) {
    // gather all form fields + submit
    event.preventDefault();
    $('#school-info').validate({ // initialize the plugin
        rules: {
            school_name:  {required:true},
            school_city:  {required:true},
            school_state: {required:true}
        }
    }).form();

    var ValidStatus = $("#school-info").valid();
    if (ValidStatus == false) {
        return false;
    }

    // otherwise, gather everything from the forms!

    $('#main-signup-form').submit();


  });

  // 
  // 
  // YUP, SIGNUP FLOW, RIGHT ABOVE ME!!!!!

  $('#top-button').click(function(event) {
    console.log('opening modal....');
    $('#myModal').modal('toggle');
  });

  $('.modal').on('hidden.bs.modal', function(event) {
     // $('body').addClass('destroy-padding');
     // $('body').removeClass('hide-scroll');
     // $("body").css("padding-right", '0px');

     console.log('closing modal'); 
    $("body").removeClass("modal-open");
  });

  $('.modal').on('shown.bs.modal', function(event) {
    // $('body').removeClass('destroy-padding');
    // $('body').addClass('hide-scroll');
    // $('body').css("padding-right", '15px');

    $("body").addClass("modal-open");
    console.log('opening modal');
  });

  $("#join.signature-modal").on('click', function(event) {
    console.log('signing in modal')
    event.preventDefault();
    $('#teacher-info').validate({ // initialize the plugin
        rules: {
            email: {
                required: true,
                email: true
            },
            password: {
                required: true
            }
        }
    }).form();

    var ValidStatus = $("#teacher-info").valid();
    if (ValidStatus == false) {
        return false;
    }
    $('#myModal').modal('toggle');
    // animate a loading gif...
    var teacher_data = $("#teacher-info").serializeArray();
    // var teacher_data = $("#teacher-info").serialize();
    var email = teacher_data[0]['value'];
    var password = teacher_data[1]['value'];

    // then AJAX req existing user....
    $.ajax({
      url: 'user_exists',
      // crossDomain: true,
      type: 'get',
      dataType: 'json',
      data: {
        email: email,
        password: password
      },
      success: function(data) {
        console.log(data);
        if (data.educator == 'false') {
          // $('body').css("padding-right", '15px');
          // $("body").addClass("hide-scroll");
          $('#chooseRoleModal').modal('toggle');
          // show a different modal here....

        } else { 
          console.log(typeof(data));
          var signature = data.educator;
          var role      = data.role;
          console.log(signature);
          console.log(role);
          var input = $('<input>').attr('type', 'hidden').attr('name', 'signature').val(signature);
          $('#teacher-info').append($(input));

          var role = $('<input>').attr('type', 'hidden').attr('name', 'role').val(role);
          $('#teacher-info').append($(role));

          // $("#teacher-info input[name='signature']").val(data);
          $('#teacher-info').submit();
        } 
      },
      error: function(xhr) {
        d = xhr;
        console.log('hey fucker, it\'s an error');
        console.log(xhr);
      }
    }); // $.ajax()

  }); // join signature modal

}); // on document ready