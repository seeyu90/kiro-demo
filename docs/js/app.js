(function () {
  "use strict";

  // 模擬資料，欄位與結構對應 warroom-data-api-prototype 的
  // MockData::ProjectProgress::RECORDS，僅供靜態展示使用。
  var RECORDS = [
    { project_name: "Project Alpha", task_name: "Initial setup", status: "completed", owner: "Alice", planned_completion_date: "2024-01-15", actual_completion_date: "2024-01-20", delay_days: 2 },
    { project_name: "Project Alpha", task_name: "Design phase", status: "completed", owner: "Bob", planned_completion_date: "2024-01-21", actual_completion_date: "2024-02-05", delay_days: 0 },
    { project_name: "Project Alpha", task_name: "Implementation", status: "completed", owner: "Charlie", planned_completion_date: "2024-02-06", actual_completion_date: "2024-02-20", delay_days: -3 },
    { project_name: "Project Beta", task_name: "Requirements gathering", status: "completed", owner: "David", planned_completion_date: "2024-02-01", actual_completion_date: "2024-02-10", delay_days: 1 },
    { project_name: "Project Beta", task_name: "Development", status: "in_progress", owner: "Eve", planned_completion_date: "2024-02-11", actual_completion_date: "2024-02-28", delay_days: 5 },
    { project_name: "Project Beta", task_name: "Testing", status: "pending", owner: "Frank", planned_completion_date: "2024-02-29", actual_completion_date: null, delay_days: null }
  ];

  var COLUMNS = [
    { key: "task_name", label: "任務名稱" },
    { key: "status", label: "狀態" },
    { key: "owner", label: "負責人" },
    { key: "planned_completion_date", label: "預計完成日期" },
    { key: "actual_completion_date", label: "實際完成日期" },
    { key: "delay_days", label: "延誤天數" }
  ];

  function groupByProject(records) {
    return records.reduce(function (groups, record) {
      var key = record.project_name;
      groups[key] = groups[key] || [];
      groups[key].push(record);
      return groups;
    }, {});
  }

  function formatValue(key, value) {
    if (value === null || value === undefined || value === "") {
      return "—";
    }
    return String(value);
  }

  function delayClass(value) {
    if (typeof value !== "number") return "";
    if (value < 0) return "delay-negative";
    if (value > 0) return "delay-positive";
    return "";
  }

  function buildTable(tasks) {
    var table = document.createElement("table");
    table.className = "project-tasks";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    COLUMNS.forEach(function (column) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = column.label;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    tasks.forEach(function (task) {
      var row = document.createElement("tr");
      COLUMNS.forEach(function (column) {
        var td = document.createElement("td");
        td.setAttribute("data-label", column.label);
        var value = task[column.key];
        td.textContent = formatValue(column.key, value);
        if (column.key === "delay_days") {
          var cls = delayClass(value);
          if (cls) td.classList.add(cls);
        }
        row.appendChild(td);
      });
      tbody.appendChild(row);
    });
    table.appendChild(tbody);

    return table;
  }

  function render(selectedProject) {
    var content = document.getElementById("content");
    content.innerHTML = "";

    var grouped = groupByProject(RECORDS);
    var projectNames = selectedProject ? [selectedProject] : Object.keys(grouped);

    if (projectNames.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無資料";
      content.appendChild(empty);
      return;
    }

    projectNames.forEach(function (projectName) {
      var tasks = grouped[projectName] || [];
      var section = document.createElement("section");
      section.className = "project-block";

      var heading = document.createElement("h2");
      heading.textContent = projectName;
      section.appendChild(heading);

      if (tasks.length === 0) {
        var emptyBlock = document.createElement("p");
        emptyBlock.className = "empty-state";
        emptyBlock.textContent = "目前無資料";
        section.appendChild(emptyBlock);
      } else {
        section.appendChild(buildTable(tasks));
      }

      content.appendChild(section);
    });
  }

  function populateProjectSelect() {
    var select = document.getElementById("project");
    var grouped = groupByProject(RECORDS);
    var allOption = document.createElement("option");
    allOption.value = "";
    allOption.textContent = "全部專案";
    select.appendChild(allOption);

    Object.keys(grouped).forEach(function (projectName) {
      var option = document.createElement("option");
      option.value = projectName;
      option.textContent = projectName;
      select.appendChild(option);
    });

    select.addEventListener("change", function () {
      render(select.value || null);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    populateProjectSelect();
    render(null);
  });
})();
