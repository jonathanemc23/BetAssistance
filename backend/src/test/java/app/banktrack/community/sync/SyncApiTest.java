package app.banktrack.community.sync;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SyncApiTest {
    @Autowired MockMvc mvc;

    MockHttpServletRequestBuilder as(String user, MockHttpServletRequestBuilder req) {
        return req.header("X-Dev-User", user).contentType(MediaType.APPLICATION_JSON);
    }

    static String save(long base, String data) {
        return "{\"baseVersion\":%d,\"data\":\"%s\"}".formatted(base, data.replace("\"", "\\\""));
    }

    @Test
    void eachAccountKeepsItsOwnDataAndPhonesCantOverwriteEachOther() throws Exception {
        mvc.perform(get("/api/sync")).andExpect(status().isUnauthorized());
        mvc.perform(as("ana", get("/api/sync"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value(0))
                .andExpect(jsonPath("$.data").doesNotExist());

        // First save from the phone.
        mvc.perform(as("ana", put("/api/sync")).content(save(0, "{\"bets\":[1]}")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1));
        mvc.perform(as("ana", put("/api/sync")).content(save(1, "{\"bets\":[1,2]}")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(2));
        mvc.perform(as("ana", get("/api/sync")))
                .andExpect(jsonPath("$.version").value(2))
                .andExpect(jsonPath("$.data").value("{\"bets\":[1,2]}"));

        // A second phone that last saw version 1 (or nothing) is told, not allowed to overwrite.
        mvc.perform(as("ana", put("/api/sync")).content(save(1, "{\"bets\":[9]}")))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.version").value(2));
        mvc.perform(as("ana", put("/api/sync")).content(save(0, "{\"bets\":[9]}")))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.version").value(2));

        // Another account sees nothing of it.
        mvc.perform(as("ben", get("/api/sync"))).andExpect(jsonPath("$.version").value(0));

        mvc.perform(as("ana", put("/api/sync")).content(save(2, ""))).andExpect(status().isBadRequest());
        mvc.perform(as("ana", delete("/api/sync"))).andExpect(status().isNoContent());
        mvc.perform(as("ana", get("/api/sync"))).andExpect(jsonPath("$.version").value(0));
    }
}
