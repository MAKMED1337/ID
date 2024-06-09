function snakeToTitle(snakeStr) {
    return snakeStr
        .split('_')                 // Split the string into an array of words
        .map(word =>                // Map over each word
            word.charAt(0).toUpperCase() + word.slice(1)  // Capitalize the first letter and concatenate with the rest of the word
        )
        .join(' ');                 // Join the array back into a single string with spaces
}

function createTable(headers) {
    // Create table element
    const table = document.createElement('table');

    // Create the header row
    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');

    headers.forEach(headerText => {
        const th = document.createElement('th');
        th.textContent = headerText;
        headerRow.appendChild(th);
    });

    thead.appendChild(headerRow);
    table.appendChild(thead);

    // Create tbody element
    const tbody = document.createElement('tbody');
    table.appendChild(tbody);

    return table;
}

async function fillTable(table, headers, data) {
    const tableBody = table.getElementsByTagName('tbody')[0];
    tableBody.innerHTML = '';

    if (data.length === 0) {
        const row = document.createElement('tr');
        const td = document.createElement('td');
        td.textContent = 'No entries found';
        td.colSpan = headers.length; // Span across all columns
        td.style.textAlign = 'center';
        row.appendChild(td);
        tableBody.appendChild(row);
        return;
    }

    data.forEach(item => {
        const row = document.createElement('tr');

        for (let key of headers)
            row.innerHTML += `<td>${item[key]}</td>`

        tableBody.appendChild(row);
    });
}

async function fetchData(path, params = {}) {
    const token = localStorage.getItem('bearerToken');

    if (!token) {
        console.error('No bearer token found in localStorage');
        window.location.href = '/static/login.html';
        return;
    }

    const headers = {
        ...params['headers'],
        'Authorization': `Bearer ${token}`,
    };
    const response = await fetch(path, {
        ...params,
        headers: headers,
    });

    if (response.status === 401) {
        window.location.href = '/static/login.html';
        return;
    }

    if (!response.ok) {
        throw Error('Network response was not ok ' + response.statusText);
    }

    return await response.json();
}

async function createTableFromFetch(path, headers, params = {}) {
    const data = await fetchData(path, params);
    const table = createTable(headers.map(snakeToTitle));
    fillTable(table, headers, data);
    return table;
}
